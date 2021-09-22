
import Foundation
import AVFoundation

public final class AnyCVPixelBufferOutput: _StatefulObjectBase, PixelBufferOutputNodeType {

  public let pixelBufferBus: EventBus<CVPixelBuffer> = .init()

  private let upstream: VideoDataOutput

  private var cancellable: EventBusCancellable?

  public init<Filter: CVPixelBufferModifying>(
    upstream: VideoDataOutput,
    filter: Filter
  ) {
    self.upstream = upstream

    if (filter is NoPixelBufferModifier) == false {
      cancellable = upstream.sampleBufferBus.addHandler { [pixelBufferBus] buffer in
        let pixelBuffer = CMSampleBufferGetImageBuffer(buffer)!
        let new = filter.perform(pixelBuffer: pixelBuffer)
        pixelBufferBus.emit(element: new)
      }
    } else {
      cancellable = upstream.sampleBufferBus.addHandler { [pixelBufferBus] buffer in
        let pixelBuffer = CMSampleBufferGetImageBuffer(buffer)!
        pixelBufferBus.emit(element: pixelBuffer)
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
