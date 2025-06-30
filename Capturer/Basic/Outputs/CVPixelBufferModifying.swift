
import AVFoundation

public protocol CVPixelBufferModifying {

  func perform(pixelBuffer: CVPixelBuffer) -> CVPixelBuffer

}

public struct NoPixelBufferModifier: CVPixelBufferModifying, Sendable {

  init() {
    
  }

  public func perform(pixelBuffer: CVPixelBuffer) -> CVPixelBuffer {
    fatalError()
  }
}
