
import Foundation

public final class AnyCVPixelBufferOutput: _StatefulObjectBase, OutputComponentType {

  public let sampleBufferBus: EventBus<CVPixelBuffer> = .init()

  private let upstream: VideoDataOutput

  private var cancellable: EventBusCancellable?

  public init(
    upstream: VideoDataOutput,
    filter: CoreImageFilter?
  ) {
    self.upstream = upstream

    if let filter = filter {
      cancellable = upstream.sampleBufferBus.addHandler { [sampleBufferBus] buffer in
        let new = filter.perform(upstream: buffer)
        sampleBufferBus.emit(event: new)
      }
    } else {
      cancellable = upstream.sampleBufferBus.addHandler { [sampleBufferBus] buffer in
        let pixelBuffer = CMSampleBufferGetImageBuffer(buffer)!
        sampleBufferBus.emit(event: pixelBuffer)
      }
    }
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
