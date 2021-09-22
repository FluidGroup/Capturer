
import AVFoundation

public final class CameraInput: _StatefulObjectBase, InputNodeType {

  public let captureDeviceInput: AVCaptureDeviceInput

  private init(input: AVCaptureDeviceInput) {
    self.captureDeviceInput = input
    super.init()
  }

  public func setUp(sessionInConfiguring: AVCaptureSession) {
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

  public static func wideAngleCamera(position: CameraPosition) -> CameraInput {

    let discoverySession = AVCaptureDevice.DiscoverySession(
      deviceTypes: [
        .builtInWideAngleCamera,
      ], mediaType: .video,
      position: {
        switch position {
        case .front: return .front
        case .back: return .back
        }
      }()
    )

    let device = discoverySession.devices.first!

    let input = try! AVCaptureDeviceInput(device: device)

    return .init(input: input)
  }

}
