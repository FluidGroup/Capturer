
import Foundation
import AVFoundation

public protocol InputNodeType: AnyObject {
  func setUp(sessionInConfiguring: AVCaptureSession)
  func tearDown(sessionInConfiguring: AVCaptureSession)
}
