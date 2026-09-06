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

  private let pipeline: Pipeline
  private let delegateProxy: _AVCaptureVideoDataOutputSampleBufferDelegateProxy

  private var observation: NSKeyValueObservation?

  private var state: State = .init() {
    didSet {
      guard oldValue != state else { return }
      update(with: state, oldState: oldValue)
    }
  }

  public override init() {

    let pipeline = Pipeline()
    self.pipeline = pipeline
    self.sampleBufferBus = pipeline.sampleBufferBus
    self.pixelBufferBus = pipeline.pixelBufferBus
    self.delegateProxy = .init(pipeline: pipeline)

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
  /// on the calling thread, so call from the thread the frames should be delivered on. One frame
  /// is delivered at a time: a frame that arrives while another is still being delivered is
  /// dropped, as the camera's would be.
  public func emit(sampleBuffer: CMSampleBuffer) {
    pipeline.publish(sampleBuffer)
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

  /// The buses, and the one rule for putting a frame on them: one at a time.
  ///
  /// Shared by `emit` and the capture delegate so every producer passes the same gate. The camera
  /// never delivers two frames at once — AVFoundation drops the ones that arrive while the
  /// delegate is busy — and any other producer gets the same treatment here: a frame arriving
  /// during a delivery is dropped, never queued and never delivered on top of the first. Handlers
  /// can therefore assume they are not entered concurrently, which `CoreImageFilter` relies on
  /// because it applies its filters in place. The lock is not recursive, so a handler must not
  /// emit back into the output it is being called from — that frame would be dropped too.
  ///
  /// A sample buffer without an image buffer is skipped rather than force-unwrapped. The camera
  /// always supplies one; a frame from anywhere else has no such guarantee.
  private final class Pipeline: @unchecked Sendable {

    let sampleBufferBus = EventBus<CMSampleBuffer>()
    let pixelBufferBus = EventBus<CVPixelBuffer>()

    private let deliveryLock = NSLock()
    private let droppedFrames = DroppedFrameLog()

    func publish(_ sampleBuffer: CMSampleBuffer) {
      guard deliveryLock.try() else {
        droppedFrames.record(reason: "a previous frame is still being delivered")
        return
      }
      defer { deliveryLock.unlock() }

      sampleBufferBus.emit(element: sampleBuffer)

      if let pixelBuffer = sampleBuffer.takeCVPixelBuffer() {
        pixelBufferBus.emit(element: pixelBuffer)
      }
    }

    /// Records a frame the capture output dropped. The buffer carries the reason and timing
    /// only — no image — so nothing here may read its pixels.
    func recordDrop(of sampleBuffer: CMSampleBuffer) {
      let reason = CMGetAttachment(
        sampleBuffer,
        key: kCMSampleBufferAttachmentKey_DroppedFrameReason,
        attachmentModeOut: nil
      ) as? String
      droppedFrames.record(reason: reason ?? "unknown")
    }
  }

  /// Counts dropped frames and reports at most once a second, so an overloaded pipeline says so
  /// without the saying adding to the overload. Drops are the only signal that delivery is not
  /// keeping up, which is why they are not discarded silently.
  private final class DroppedFrameLog: @unchecked Sendable {

    private static let reportInterval: TimeInterval = 1

    private let lock = NSLock()
    private var droppedSinceLastReport = 0
    private var lastReport: TimeInterval = 0

    func record(reason: String) {
      lock.lock()
      droppedSinceLastReport += 1
      let now = ProcessInfo.processInfo.systemUptime
      guard now - lastReport >= Self.reportInterval else {
        lock.unlock()
        return
      }
      let count = droppedSinceLastReport
      droppedSinceLastReport = 0
      lastReport = now
      lock.unlock()

      Log.debug(.capture, "Dropped \(count) frame(s); latest reason: \(reason)")
    }
  }

  private final class _AVCaptureVideoDataOutputSampleBufferDelegateProxy: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    private let pipeline: Pipeline

    init(pipeline: Pipeline) {
      self.pipeline = pipeline
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
      pipeline.recordDrop(of: sampleBuffer)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
      pipeline.publish(sampleBuffer)
    }

  }

}
