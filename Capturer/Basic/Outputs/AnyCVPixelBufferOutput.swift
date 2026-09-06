
import Foundation
import AVFoundation
@preconcurrency import CoreMedia

extension CVBuffer: @retroactive @unchecked Sendable {}

public class AnyCVPixelBufferOutput: PixelBufferOutputNodeType, @unchecked Sendable {

  public let pixelBufferBus: EventBus<CVPixelBuffer> = .init()

  private let upstream: VideoDataOutput

  private var cancellable: EventBusCancellable? = nil

  public init<Filter: CVPixelBufferModifying & Sendable>(
    upstream: VideoDataOutput,
    filter: Filter
  ) {
    self.upstream = upstream

    // Runs on the upstream's delivery thread, synchronously, like everything on a bus: the
    // filter is applied and the result published before the next frame can arrive.
    let pixelBufferBus = self.pixelBufferBus
    if filter is NoPixelBufferModifier {
      cancellable = upstream.sampleBufferBus.addHandler { buffer in
        guard let pixelBuffer = buffer.takeCVPixelBuffer() else { return }
        pixelBufferBus.emit(element: pixelBuffer)
      }
    } else {
      cancellable = upstream.sampleBufferBus.addHandler { buffer in
        guard let pixelBuffer = buffer.takeCVPixelBuffer() else { return }
        pixelBufferBus.emit(element: filter.perform(pixelBuffer: pixelBuffer))
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
