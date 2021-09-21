
import AVFoundation

public final class CameraInput: _StatefulObjectBase, InputComponentType {

  public let captureDeviceInput: AVCaptureDeviceInput

  public override init() {

    let discoverySession = AVCaptureDevice.DiscoverySession(
      deviceTypes: [
        .builtInWideAngleCamera,
      ], mediaType: .video,
      position: .back
    )

    let input = try! AVCaptureDeviceInput(device: discoverySession.devices.first!)

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
