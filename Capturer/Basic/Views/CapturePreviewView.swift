import AVFoundation
import SwiftUI
import UIKit

/// SwiftUI camera preview backed by `AVCaptureVideoPreviewLayer`.
///
/// Attaches the preview layer directly to the `CaptureBody`'s session and
/// drives the layer connection's `videoRotationAngle` from
/// `AVCaptureDevice.RotationCoordinator.videoRotationAngleForHorizonLevelPreview`,
/// so the rendered preview is always upright regardless of physical
/// device orientation — including iPad rotations.
///
/// Preferred over wrapping `PixelBufferView` for the live preview path.
/// `PixelBufferView` is still appropriate when the preview must be processed
/// through a `CVPixelBuffer` pipeline (Core Image filters, custom shaders, etc.).
public struct CapturePreviewView: UIViewRepresentable {
    public let captureBody: CaptureBody
    public var videoGravity: AVLayerVideoGravity

    public init(
        captureBody: CaptureBody,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill
    ) {
        self.captureBody = captureBody
        self.videoGravity = videoGravity
    }

    public func makeUIView(context: Context) -> _CapturePreviewUIView {
        let view = _CapturePreviewUIView()
        view.previewLayer.session = captureBody.session
        view.previewLayer.videoGravity = videoGravity
        context.coordinator.attach(view: view, session: captureBody.session)
        return view
    }

    public func updateUIView(_ uiView: _CapturePreviewUIView, context: Context) {
        if uiView.previewLayer.videoGravity != videoGravity {
            uiView.previewLayer.videoGravity = videoGravity
        }
    }

    public static func dismantleUIView(_ uiView: _CapturePreviewUIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    public final class Coordinator: Sendable {
        private weak var view: _CapturePreviewUIView?
        private var session: AVCaptureSession?
        private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
        private var rotationObservation: NSKeyValueObservation?
        private var inputsObservation: NSKeyValueObservation?

        /// Identifies the current attachment, so a device lookup still in flight when the
        /// view is detached (or re-attached) is discarded rather than wiring a stale
        /// device to whatever layer happens to be current by the time it lands.
        private var wiringGeneration: UInt64 = 0

        func attach(view: _CapturePreviewUIView, session: AVCaptureSession) {
            self.view = view
            self.session = session
            wiringGeneration &+= 1
            wireRotationIfPossible()
            inputsObservation = session.observe(
                \.inputs,
                options: [.new]
            ) { [weak self] _, _ in
                Task { @MainActor in
                    self?.wireRotationIfPossible()
                }
            }
        }

        func detach() {
            wiringGeneration &+= 1
            rotationObservation?.invalidate()
            rotationObservation = nil
            inputsObservation?.invalidate()
            inputsObservation = nil
            rotationCoordinator = nil
            session = nil
            view = nil
        }

        private func wireRotationIfPossible() {
            guard rotationCoordinator == nil,
                  view != nil,
                  let session
            else { return }

            let boxedSession = UncheckedSendable(session)
            let generation = wiringGeneration

            // `AVCaptureSession.inputs` acquires the session's lock, and a background
            // reconfiguration holds that lock for the whole of its
            // beginConfiguration/commitConfiguration block. Reading it off the main actor
            // keeps the main thread out of that lock entirely: taking it here on main was
            // one half of a deadlock against a session being configured from a background
            // task, and even with the other half fixed it stalls the UI for the length of
            // a reconfiguration.
            Task.detached { [weak self] in
                let device = Self.firstVideoDevice(in: boxedSession)
                await self?.finishWiring(with: device, generation: generation)
            }
        }

        private nonisolated static func firstVideoDevice(
            in session: UncheckedSendable<AVCaptureSession>
        ) -> UncheckedSendable<AVCaptureDevice?> {
            UncheckedSendable(
                session.wrapped.inputs
                    .compactMap { ($0 as? AVCaptureDeviceInput)?.device }
                    .first
            )
        }

        private func finishWiring(
            with device: UncheckedSendable<AVCaptureDevice?>,
            generation: UInt64
        ) {
            guard generation == wiringGeneration,
                  rotationCoordinator == nil,
                  let device = device.wrapped,
                  let view
            else { return }

            let layer = view.previewLayer
            let coordinator = AVCaptureDevice.RotationCoordinator(
                device: device,
                previewLayer: layer
            )
            rotationCoordinator = coordinator
            Self.apply(
                angle: coordinator.videoRotationAngleForHorizonLevelPreview,
                on: layer
            )
            rotationObservation = coordinator.observe(
                \.videoRotationAngleForHorizonLevelPreview,
                options: [.new]
            ) { [weak self] _, change in
                guard let newAngle = change.newValue else { return }
                Task { @MainActor in
                    guard let layer = self?.view?.previewLayer else { return }
                    Self.apply(angle: newAngle, on: layer)
                }
            }
        }

        private static func apply(angle: CGFloat, on layer: AVCaptureVideoPreviewLayer) {
            guard let connection = layer.connection,
                  connection.isVideoRotationAngleSupported(angle) else { return }
            connection.videoRotationAngle = angle
        }
    }
}

public final class _CapturePreviewUIView: UIView {
    public override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    /// The backing `AVCaptureVideoPreviewLayer`.
    ///
    /// Force-cast is safe: `layerClass` above guarantees the type at runtime.
    public var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
