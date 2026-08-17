import AVFoundation
import CoreMedia
import Foundation

enum Utils {

  static func checkIfCanUseCameraAccordingToPrivacySensitiveData() -> Bool {
    Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil
  }

}

/// Carries a value that is not statically `Sendable` across an isolation boundary.
///
/// AVFoundation's capture types (`AVCaptureSession`, `AVCaptureDevice`,
/// `AVCaptureConnection`) are documented as usable from any thread but are not annotated
/// `Sendable`. Where this package deliberately hands one to another executor, this box
/// states that intent at the point of use and confines the exemption to the single value
/// being passed, instead of weakening an entire file with `@preconcurrency import`.
struct UncheckedSendable<Wrapped>: @unchecked Sendable {

  let wrapped: Wrapped

  init(_ wrapped: Wrapped) {
    self.wrapped = wrapped
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
