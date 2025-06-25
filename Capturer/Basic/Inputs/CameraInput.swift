
@preconcurrency import AVFoundation

public final class CameraInput: _StatefulObjectBase, DeviceInputNodeType, @unchecked Sendable {

  public var device: AVCaptureDevice {
    captureDeviceInput.device
  }

  public let captureDeviceInput: AVCaptureDeviceInput

  private init(input: AVCaptureDeviceInput) {
    self.captureDeviceInput = input
    super.init()
  }

  public func setUp(sessionInConfiguring: AVCaptureSession) {
      // Are those actually thread safe ?
    sessionInConfiguring.addInput(captureDeviceInput)
  }

  public func tearDown(sessionInConfiguring: AVCaptureSession) {
    sessionInConfiguring.removeInput(captureDeviceInput)
  }
}

extension CameraInput {

  public enum CameraPosition {
    case front
    case back
  }

  enum Error: Swift.Error {
    case couldNotFindCamera
  }

  public static  func bestBuiltInDevice(position: CameraPosition) throws -> CameraInput {
    let discoverySession = AVCaptureDevice.DiscoverySession(
      deviceTypes:
        [
          .builtInWideAngleCamera,
          .builtInUltraWideCamera,
          .builtInTelephotoCamera
        ],
      mediaType: .video,
      position: {
        switch position {
        case .front: .front
        case .back: .back
        }
      }())
    guard let device = discoverySession.devices.first else {
      throw Error.couldNotFindCamera
    }
    let input = try AVCaptureDeviceInput(device: device)
    return .init(input: input)
  }
}
