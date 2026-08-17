#!/usr/bin/env python3
"""
Guards the two invariants that keep AVCaptureSession configuration from deadlocking
against the main thread.

Background
----------
`AVCaptureDevice.RotationCoordinator.init` blocks internally on the main queue, even when
`previewLayer` is nil. `PreviewOutput.didChange(connections:)` is delivered synchronously
by KVO from inside `-[AVCaptureSession addOutput:]`, i.e. while the configuring thread
holds the session lock. Building the coordinator there, while any main-thread code is
waiting on that same session lock (`AVCaptureSession.inputs` is the one that bit us),
produces an unrecoverable ABBA deadlock:

    background : holds session lock  ->  waits for main queue
    main       : owns main queue     ->  waits for session lock

Invariants
----------
A. PreviewOutput must never construct a RotationCoordinator synchronously inside
   didChange(connections:). It must hop to the main actor first.
B. CapturePreviewView must never read `AVCaptureSession.inputs` from main-actor-isolated
   code; the read has to happen off the main actor.

Run:  python3 Tools/check_camera_deadlock_invariants.py [repo-root]
Exit: 0 if both invariants hold, 1 otherwise.
"""

import re
import sys
from pathlib import Path

PREVIEW_OUTPUT = Path("Capturer/Basic/Outputs/PreviewOutput.swift")
PREVIEW_VIEW = Path("Capturer/Basic/Views/CapturePreviewView.swift")

FUNC_RE = re.compile(r"^\s*(?:@\w+\s+)*(?:private|public|open|internal|fileprivate)?\s*"
                     r"(?:nonisolated\s+)?(?:static\s+|override\s+|final\s+|class\s+)*func\s+(\w+)")

# The full type name; `installRotationCoordinator(` must not count as a construction.
CONSTRUCTS_COORDINATOR = "AVCaptureDevice.RotationCoordinator("
MAIN_ACTOR_HOP = re.compile(r"Task\s*(?:\.detached\s*)?\{\s*@MainActor|await\s+MainActor\.run")
# `\.inputs` is a KVO key path, not a property read, so it is exempt.
READS_INPUTS = re.compile(r"(?<!\\)\.inputs\b")


def strip_comment(line):
    """Drops a trailing `//` comment.

    Prose in this package's doc comments legitimately names `AVCaptureSession.inputs`
    and the rotation coordinator, so matching raw lines produces false positives.
    """
    index = line.find("//")
    return line if index == -1 else line[:index]


def enclosing_functions(lines):
    """Yields (line_index, code_without_comment, enclosing_function_name, declaration_line)."""
    current_name = None
    current_decl = ""
    for index, raw in enumerate(lines):
        line = strip_comment(raw)
        match = FUNC_RE.match(line)
        if match:
            current_name = match.group(1)
            current_decl = line
        yield index, line, current_name, current_decl


def check_preview_output(root):
    path = root / PREVIEW_OUTPUT
    if not path.exists():
        return [f"missing file: {PREVIEW_OUTPUT}"]

    lines = path.read_text().splitlines()
    problems = []
    hop_seen_in_function = {}
    found_construction = False

    for index, line, func, _decl in enclosing_functions(lines):
        if func and MAIN_ACTOR_HOP.search(line):
            hop_seen_in_function[func] = index

        if CONSTRUCTS_COORDINATOR not in line:
            continue
        found_construction = True

        if func == "didChange":
            problems.append(
                f"{PREVIEW_OUTPUT}:{index + 1}: didChange(connections:) constructs "
                f"AVCaptureDevice.RotationCoordinator synchronously. didChange runs while "
                f"the AVCaptureSession lock is held and that initializer blocks on the "
                f"main queue — this is the camera-startup deadlock. Hop to the main actor "
                f"first."
            )
        elif hop_seen_in_function.get(func) is None or hop_seen_in_function[func] > index:
            problems.append(
                f"{PREVIEW_OUTPUT}:{index + 1}: {func}() constructs an "
                f"AVCaptureDevice.RotationCoordinator without first hopping to the main "
                f"actor."
            )

    if not found_construction:
        problems.append(
            f"{PREVIEW_OUTPUT}: no AVCaptureDevice.RotationCoordinator construction found "
            f"at all — this check is no longer testing anything and needs updating."
        )
    return problems


def check_preview_view(root):
    path = root / PREVIEW_VIEW
    if not path.exists():
        return [f"missing file: {PREVIEW_VIEW}"]

    lines = path.read_text().splitlines()
    problems = []
    found_read = False

    for index, line, func, decl in enclosing_functions(lines):
        if not READS_INPUTS.search(line):
            continue
        found_read = True
        if "nonisolated" in decl:
            continue
        problems.append(
            f"{PREVIEW_VIEW}:{index + 1}: {func}() reads AVCaptureSession.inputs from "
            f"main-actor isolated code. That takes the session lock on the main thread and "
            f"can block for the length of a background reconfiguration. Read it from a "
            f"`nonisolated` context instead."
        )

    if not found_read:
        problems.append(
            f"{PREVIEW_VIEW}: no AVCaptureSession.inputs read found at all — this check "
            f"is no longer testing anything and needs updating."
        )
    return problems


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    problems = check_preview_output(root) + check_preview_view(root)

    if problems:
        print(f"FAIL — camera deadlock invariants violated in {root}:")
        for p in problems:
            print(f"  - {p}")
        return 1

    print(f"PASS — camera deadlock invariants hold in {root}")
    print("  A. RotationCoordinator is only built after a main-actor hop.")
    print("  B. AVCaptureSession.inputs is never read from main-actor isolated code.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
