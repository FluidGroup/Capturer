import Foundation
import CoreMedia
import AVFoundation

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
