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

        func attach(view: _CapturePreviewUIView, session: AVCaptureSession) {
            self.view = view
            self.session = session
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
                  let view,
                  let session
            else { return }
            let device = session.inputs
                .compactMap { ($0 as? AVCaptureDeviceInput)?.device }
                .first
            guard let device else { return }

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
