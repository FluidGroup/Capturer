
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
  /// The active format is kept when it can deliver that rate and fits `maximumDimensions`. When
  /// it cannot — the photo preset's full-sensor format tops out at 30 — the largest format of
  /// the same pixel format that can, and fits, is chosen instead, and the session's preset gives
  /// way to it (`AVCaptureSession.Preset.inputPriority`). The dimensions actually in use are
  /// returned so the caller can say so.
  ///
  /// - Parameter maximumDimensions: The largest frame the caller wants; nil accepts the largest
  ///   the camera offers at that rate. A 4K format is what an iPhone offers at 60 fps, and a
  ///   minute of it is a couple of hundred megabytes — far more than footage meant to stand in
  ///   for a preview needs.
  ///
  /// Call once the input is attached and the session is configured; a later preset change
  /// would undo it.
  @discardableResult
  public func setFrameRate(
    _ framesPerSecond: Double,
    maximumDimensions: CMVideoDimensions? = nil
  ) throws -> CMVideoDimensions {
    let device = self.device
    let current = device.activeFormat

    func fits(_ format: AVCaptureDevice.Format) -> Bool {
      guard let maximumDimensions else { return true }
      let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
      return dimensions.width <= maximumDimensions.width && dimensions.height <= maximumDimensions.height
    }

    let format: AVCaptureDevice.Format
    if current.supportsFrameRate(framesPerSecond), fits(current) {
      format = current
    } else {
      let currentSubType = CMFormatDescriptionGetMediaSubType(current.formatDescription)
      let candidates = device.formats.filter {
        CMFormatDescriptionGetMediaSubType($0.formatDescription) == currentSubType
          && $0.supportsFrameRate(framesPerSecond)
          && fits($0)
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
    // The range's own duration where the asked-for rate is its ceiling. A duration built from
    // the rate can land a rounding error short of the range, and a frame duration outside the
    // format's ranges is an exception, not an error.
    guard let frameDuration = format.frameDuration(for: framesPerSecond) else {
      throw Error.frameRateUnsupported(framesPerSecond)
    }
    device.activeVideoMinFrameDuration = frameDuration
    device.activeVideoMaxFrameDuration = frameDuration

    return CMVideoFormatDescriptionGetDimensions(format.formatDescription)
  }
}

extension AVCaptureDevice.Format {

  fileprivate func supportsFrameRate(_ framesPerSecond: Double) -> Bool {
    frameRateRange(containing: framesPerSecond) != nil
  }

  fileprivate func frameRateRange(containing framesPerSecond: Double) -> AVFrameRateRange? {
    videoSupportedFrameRateRanges.first {
      $0.minFrameRate <= framesPerSecond && framesPerSecond <= $0.maxFrameRate
    }
  }

  /// The frame duration for `framesPerSecond` within this format's ranges, or nil when no range
  /// contains it.
  fileprivate func frameDuration(for framesPerSecond: Double) -> CMTime? {
    guard let range = frameRateRange(containing: framesPerSecond) else { return nil }
    if abs(framesPerSecond - range.maxFrameRate) < 0.001 {
      return range.minFrameDuration
    }
    if abs(framesPerSecond - range.minFrameRate) < 0.001 {
      return range.maxFrameDuration
    }
    return CMTime(seconds: 1 / framesPerSecond, preferredTimescale: 1_000_000)
  }

  fileprivate var pixelCount: Int {
    let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
    return Int(dimensions.width) * Int(dimensions.height)
  }
}
