
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

  public enum Error: Swift.Error {
    case couldNotFindCamera
    /// No format of the camera's current pixel format delivers this many frames per second.
    case frameRateUnsupported(Double)
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

  /// Runs the camera at `framesPerSecond`.
  ///
  /// The active format is kept when it can deliver that rate. When it cannot — the photo
  /// preset's full-sensor format tops out at 30 — the largest format of the same pixel format
  /// that can is chosen instead, and the session's preset gives way to it
  /// (`AVCaptureSession.Preset.inputPriority`), so the frames are smaller than the preset's
  /// would have been. The dimensions actually in use are returned so the caller can say so.
  ///
  /// Call once the input is attached and the session is configured; a later preset change
  /// would undo it.
  @discardableResult
  public func setFrameRate(_ framesPerSecond: Double) throws -> CMVideoDimensions {
    let device = self.device
    let current = device.activeFormat

    let format: AVCaptureDevice.Format
    if current.supportsFrameRate(framesPerSecond) {
      format = current
    } else {
      let currentSubType = CMFormatDescriptionGetMediaSubType(current.formatDescription)
      let candidates = device.formats.filter {
        CMFormatDescriptionGetMediaSubType($0.formatDescription) == currentSubType
          && $0.supportsFrameRate(framesPerSecond)
      }
      guard let largest = candidates.max(by: { $0.pixelCount < $1.pixelCount }) else {
        throw Error.frameRateUnsupported(framesPerSecond)
      }
      format = largest
    }

    try device.lockForConfiguration()
    defer { device.unlockForConfiguration() }

    if format !== current {
      device.activeFormat = format
    }
    let frameDuration = CMTime(value: 1, timescale: CMTimeScale(framesPerSecond.rounded()))
    device.activeVideoMinFrameDuration = frameDuration
    device.activeVideoMaxFrameDuration = frameDuration

    return CMVideoFormatDescriptionGetDimensions(format.formatDescription)
  }
}

extension AVCaptureDevice.Format {

  fileprivate func supportsFrameRate(_ framesPerSecond: Double) -> Bool {
    videoSupportedFrameRateRanges.contains {
      $0.minFrameRate <= framesPerSecond && framesPerSecond <= $0.maxFrameRate
    }
  }

  fileprivate var pixelCount: Int {
    let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
    return Int(dimensions.width) * Int(dimensions.height)
  }
}
