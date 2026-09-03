@preconcurrency import AVFoundation
@preconcurrency import CoreMedia

extension CMSampleBuffer: @unchecked @retroactive Sendable {}

import Foundation

open class VideoDataOutput: _StatefulObjectBase, SampleBufferOutputNodeType, PixelBufferOutputNodeType, @unchecked Sendable {

  public struct State: Equatable {
    public var isVideoMirrored: Bool = false
  }

  private actor Handlers {
      var didOutput: @Sendable (CMSampleBuffer) -> Void = { _ in }

      func runOutput(buffer: CMSampleBuffer) {
          self.didOutput(buffer)
      }

      func setDidOutput(_ didOutput: @escaping @Sendable (CMSampleBuffer) -> Void) {
        self.didOutput = didOutput
    }
  }

  public let sampleBufferBus: EventBus<CMSampleBuffer> = .init()
  public let pixelBufferBus: EventBus<CVPixelBuffer> = .init()

  public let output = AVCaptureVideoDataOutput()

  private let delegateProxy = _AVCaptureVideoDataOutputSampleBufferDelegateProxy()

  private var observation: NSKeyValueObservation?

  private var state: State = .init() {
    didSet {
      guard oldValue != state else { return }
      update(with: state, oldState: oldValue)
    }
  }

  public override init() {

    super.init()

    let queue = DispatchQueue(label: "Capturer.VideoDataOutput")

    output.setSampleBufferDelegate(delegateProxy, queue: queue)

      Task {
          await delegateProxy.handlers.setDidOutput({ [sampleBufferBus, pixelBufferBus] sampleBuffer in
            Task {
              await Self.publish(
                sampleBuffer,
                sampleBufferBus: sampleBufferBus,
                pixelBufferBus: pixelBufferBus
              )
            }
          })
      }

    observation = output.observe(\.connections, options: [.initial, .new]) { [weak self] output, _ in
      guard let self = self else { return }
      self.didChange(connections: output.connections)
    }

    update(with: state, oldState: nil)
  }

  /// Publishes a frame that did not come from the capture session.
  ///
  /// Frames reach subscribers by exactly the same route whether the camera produced them or
  /// something else did, which is what lets a recorded video stand in for a camera without a
  /// second pipeline existing alongside the real one. Everything downstream of the buses — the
  /// preview, filters, the views — consumes `CVPixelBuffer` and has no way to tell, or care.
  public func emit(sampleBuffer: CMSampleBuffer) {
    Task { [sampleBufferBus, pixelBufferBus] in
      await Self.publish(
        sampleBuffer,
        sampleBufferBus: sampleBufferBus,
        pixelBufferBus: pixelBufferBus
      )
    }
  }

  /// The one place a frame becomes an event, whatever produced it.
  ///
  /// A sample buffer without an image buffer is skipped rather than force-unwrapped. The camera
  /// always supplies one, so the previous `unsafelyUnwrapped` never fired — but a frame arriving
  /// from anywhere else has no such guarantee, and a crash is a poor way to learn that.
  private static func publish(
    _ sampleBuffer: CMSampleBuffer,
    sampleBufferBus: EventBus<CMSampleBuffer>,
    pixelBufferBus: EventBus<CVPixelBuffer>
  ) async {
    await sampleBufferBus.emit(element: sampleBuffer)

    if await pixelBufferBus.hasTargets, let pixelBuffer = sampleBuffer.takeCVPixelBuffer() {
      await pixelBufferBus.emit(element: pixelBuffer)
    }
  }

  open func didChange(connections: [AVCaptureConnection]) {
    update(with: state, oldState: nil)
  }

  public func setUp(sessionInConfiguring: AVCaptureSession) {
    sessionInConfiguring.addOutput(output)
  }

  public func tearDown(sessionInConfiguring: AVCaptureSession) {
    sessionInConfiguring.removeOutput(output)
  }

  public func setIsMirroringEnabled(_ isEnabled: Bool) {
    state.isVideoMirrored = isEnabled
  }

  private func update(with newState: State, oldState: State?) {

    if newState.isVideoMirrored != oldState?.isVideoMirrored {

      output.connections.forEach {
        $0.isVideoMirrored = newState.isVideoMirrored
      }

    }

  }

  private final class _AVCaptureVideoDataOutputSampleBufferDelegateProxy: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    let handlers: Handlers = .init()

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {

    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let handlers = handlers
        Task {
           await handlers.runOutput(buffer: sampleBuffer)
        }
    }

  }

}
