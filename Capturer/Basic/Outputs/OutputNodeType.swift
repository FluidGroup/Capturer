
import Foundation
import AVFoundation

public protocol OutputNodeType: Sendable {
  func setUp(sessionInConfiguring: AVCaptureSession)
  func tearDown(sessionInConfiguring: AVCaptureSession)
}

public protocol PixelBufferOutputNodeType: OutputNodeType {
  var pixelBufferBus: EventBus<CVPixelBuffer> { get }
}

public protocol SampleBufferOutputNodeType: OutputNodeType {
  var sampleBufferBus: EventBus<CMSampleBuffer> { get }
}
