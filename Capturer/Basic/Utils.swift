import AVFoundation
import CoreMedia
import Foundation

enum Utils {

  static func checkIfCanUseCameraAccordingToPrivacySensitiveData() -> Bool {
    Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil
  }

}

extension CMSampleBuffer {

  @inline(__always)
  public func takeCVPixelBuffer() -> CVPixelBuffer? {
    CMSampleBufferGetImageBuffer(self)
  }
}

extension AVCaptureConnection {

  func _capturer_debuggingInfo() -> [String : Any] {

    return [
      "isActive" : isActive,
      "orientation": videoOrientation._capturer_localizedDescription(),
      "isVideoMirrored" : isVideoMirrored,
      "automaticallyAdjustsVideoMirroring" : automaticallyAdjustsVideoMirroring,
      "inputPorts" : inputPorts
    ]
  }

}

extension AVCaptureVideoOrientation {

  func _capturer_localizedDescription() -> String {
    switch self {
    case .portrait:
      return "portrait"
    case .portraitUpsideDown:
      return "portraitUpsideDown"
    case .landscapeRight:
      return "landscapeRight"
    case .landscapeLeft:
      return "landscapeLeft"
    @unknown default:
      return ""
    }
  }
}
