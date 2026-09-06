@preconcurrency import AVFoundation
@preconcurrency import CoreMedia

extension CMSampleBuffer: @unchecked @retroactive Sendable {}

import Foundation

open class VideoDataOutput: _StatefulObjectBase, SampleBufferOutputNodeType, PixelBufferOutputNodeType, @unchecked Sendable {

  public struct State: Equatable {
    public var isVideoMirrored: Bool = false
  }

  public let sampleBufferBus: EventBus<CMSampleBuffer>
  public let pixelBufferBus: EventBus<CVPixelBuffer>

  public let output = AVCaptureVideoDataOutput()

  private let delegateProxy: _AVCaptureVideoDataOutputSampleBufferDelegateProxy

  private var observation: NSKeyValueObservation?

  private var state: State = .init() {
    didSet {
      guard oldValue != state else { return }
      update(with: state, oldState: oldValue)
    }
  }

  public override init() {

    let sampleBufferBus = EventBus<CMSampleBuffer>()
    let pixelBufferBus = EventBus<CVPixelBuffer>()
    self.sampleBufferBus = sampleBufferBus
    self.pixelBufferBus = pixelBufferBus
    self.delegateProxy = .init(sampleBufferBus: sampleBufferBus, pixelBufferBus: pixelBufferBus)

    super.init()

    // Frames are published on this queue, synchronously, straight from the delegate callback:
    // no hop, no task, nothing queued. A handler that cannot keep up costs frames — AVFoundation
    // drops the ones that arrive while the callback is still busy — which is the behaviour a
    // camera pipeline is meant to have.
    let queue = DispatchQueue(label: "Capturer.VideoDataOutput")
    output.setSampleBufferDelegate(delegateProxy, queue: queue)

    observation = output.observe(\.connections, options: [.initial, .new]) { [weak self] output, _ in
      guard let self = self else { return }
      self.didChange(connections: output.connections)
    }

    update(with: state, oldState: nil)
  }

  /// Publishes a frame that did not come from the capture session.
  ///
  /// This is how recorded footage stands in for a camera: whatever produced the frame hands it
  /// over here and it takes exactly the route a captured frame takes. Synchronous — the buses run
  /// on the calling thread, so call from the thread the frames should be delivered on.
  public func emit(sampleBuffer: CMSampleBuffer) {
    Self.publish(sampleBuffer, sampleBufferBus: sampleBufferBus, pixelBufferBus: pixelBufferBus)
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
  ) {
    sampleBufferBus.emit(element: sampleBuffer)

    if pixelBufferBus.hasTargets, let pixelBuffer = sampleBuffer.takeCVPixelBuffer() {
      pixelBufferBus.emit(element: pixelBuffer)
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

    private let sampleBufferBus: EventBus<CMSampleBuffer>
    private let pixelBufferBus: EventBus<CVPixelBuffer>

    init(sampleBufferBus: EventBus<CMSampleBuffer>, pixelBufferBus: EventBus<CVPixelBuffer>) {
      self.sampleBufferBus = sampleBufferBus
      self.pixelBufferBus = pixelBufferBus
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {

    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
      VideoDataOutput.publish(sampleBuffer, sampleBufferBus: sampleBufferBus, pixelBufferBus: pixelBufferBus)
    }

  }

}
