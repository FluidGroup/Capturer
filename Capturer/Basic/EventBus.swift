
import Foundation

public final class EventBusCancellable: Hashable, @unchecked Sendable {

  public static func == (lhs: EventBusCancellable, rhs: EventBusCancellable) -> Bool {
    lhs === rhs
  }

  public func hash(into hasher: inout Hasher) {
    ObjectIdentifier(self).hash(into: &hasher)
  }

  private let _onCancel: (EventBusCancellable) -> Void

  init(onCancel: @escaping (EventBusCancellable) -> Void) {
    self._onCancel = onCancel
  }

  public func cancel() {
    _onCancel(self)
  }
}

/// Hands every element to every handler, synchronously, on the thread that emits it.
///
/// This is the delegate model AVFoundation itself uses, and it is what keeps a frame pipeline
/// honest: a handler runs while the producer waits, so a slow handler costs the producer frames
/// — the camera drops them, a video source skips to the current one — and nothing is ever queued
/// up behind it. Handlers should therefore do little: take the element, hand it to their own
/// queue, return. A handler added after an element was emitted does not see that element; a
/// handler cancelled during an emit may still receive that one element.
///
/// Handlers are serialised only per producer thread: a bus emitted to from several threads
/// runs a handler concurrently with itself, so a handler must guard any state it shares. A
/// handler must never block waiting on the main thread — the producer is waiting on it.
/// Cancelling is synchronous and safe from anywhere, including from a `deinit` that runs while
/// this bus releases a handler.
public final class EventBus<Element: Sendable>: @unchecked Sendable {
  public typealias Handler = @Sendable (Element) -> Void

  private let lock = NSLock()
  private var targets: ContiguousArray<(cancellable: EventBusCancellable, handler: Handler)> = .init()

  public init() {
  }

  /// Whether anyone is listening — a producer can skip work that nobody would receive.
  public var hasTargets: Bool {
    lock.lock()
    defer { lock.unlock() }
    return !targets.isEmpty
  }

  public func addHandler(_ handler: @escaping Handler) -> EventBusCancellable {
    let cancellable = EventBusCancellable { [weak self] cancellable in
      self?.removeTarget(matchingCancellable: cancellable)
    }
    lock.lock()
    targets.append((cancellable, handler))
    lock.unlock()
    return cancellable
  }

  public func emit(element: Element) {
    lock.lock()
    let handlers = targets
    lock.unlock()
    for target in handlers {
      target.handler(element)
    }
  }

  private func removeTarget(matchingCancellable: EventBusCancellable) {
    lock.lock()
    // Each cancellable is created here and appended exactly once, so a single index is exact.
    let removedIndex = targets.firstIndex { $0.cancellable == matchingCancellable }
    let removed = removedIndex.map { targets.remove(at: $0) }
    lock.unlock()
    // The handler is released here, outside the lock: it may be the last owner of something
    // whose deinit cancels on this bus, and the lock is not recursive.
    withExtendedLifetime(removed) {}
  }
}
