
import Foundation
import AVFoundation

public protocol OutputComponentType: AnyObject {
  func setUp(sessionInConfiguring: AVCaptureSession)
  func tearDown(sessionInConfiguring: AVCaptureSession)
}
