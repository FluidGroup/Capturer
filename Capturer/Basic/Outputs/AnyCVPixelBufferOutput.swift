
import Foundation
import AVFoundation

public final class AnyCVPixelBufferOutput: _StatefulObjectBase, OutputComponentType {

  public let sampleBufferBus: EventBus<CVPixelBuffer> = .init()

  private let upstream: VideoDataOutput

  private var cancellable: EventBusCancellable?

  public init<Filter: CVPixelBufferModifying>(
    upstream: VideoDataOutput,
    filter: Filter
  ) {
    self.upstream = upstream

    if (filter is NoPixelBufferModifier) == false {
      cancellable = upstream.sampleBufferBus.addHandler { [sampleBufferBus] buffer in
        let pixelBuffer = CMSampleBufferGetImageBuffer(buffer)!
        let new = filter.perform(pixelBuffer: pixelBuffer)
        sampleBufferBus.emit(event: new)
      }
    } else {
      cancellable = upstream.sampleBufferBus.addHandler { [sampleBufferBus] buffer in
        let pixelBuffer = CMSampleBufferGetImageBuffer(buffer)!
        sampleBufferBus.emit(event: pixelBuffer)
      }
    }
  }

  public convenience init(
    upstream: VideoDataOutput
  ) {
    self.init(upstream: upstream, filter: NoPixelBufferModifier())
  }

  deinit {
    cancellable?.cancel()
  }

  public func setUp(sessionInConfiguring: AVCaptureSession) {
    upstream.setUp(sessionInConfiguring: sessionInConfiguring)
  }

  public func tearDown(sessionInConfiguring: AVCaptureSession) {
    upstream.tearDown(sessionInConfiguring: sessionInConfiguring)
  }

}
