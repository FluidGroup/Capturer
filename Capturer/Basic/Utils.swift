import Foundation

enum Utils {

  static func checkIfCanUseCameraAccordingToPrivacySensitiveData() -> Bool {
    Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil
  }

}
