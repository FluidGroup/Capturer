
import Foundation
import AVFoundation

public protocol InputNodeType: AnyObject {
  func setUp(sessionInConfiguring: AVCaptureSession)
  func tearDown(sessionInConfiguring: AVCaptureSession)
}

public protocol DeviceInputNodeType: InputNodeType {
  var device: AVCaptureDevice { get }
}
