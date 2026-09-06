
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

    let format: AVCaptureDevice.Format
    if current.supportsFrameRate(framesPerSecond), current.fits(within: maximumDimensions) {
      format = current
    } else {
      let currentSubType = CMFormatDescriptionGetMediaSubType(current.formatDescription)
      let candidates = device.formats.filter {
        CMFormatDescriptionGetMediaSubType($0.formatDescription) == currentSubType
          && $0.supportsFrameRate(framesPerSecond)
          && $0.fits(within: maximumDimensions)
      }
      guard let preferred = candidates.max(by: { $0.preferenceKey < $1.preferenceKey }) else {
        throw Error.frameRateUnsupported(framesPerSecond)
      }
      format = preferred
    }

    // Resolved before the lock so that nothing on the device has changed when the rate turns
    // out to be unavailable.
    guard let frameDuration = format.frameDuration(for: framesPerSecond) else {
      throw Error.frameRateUnsupported(framesPerSecond)
    }

    try device.lockForConfiguration()
    defer { device.unlockForConfiguration() }

    if format !== current {
      device.activeFormat = format
    }
    device.activeVideoMinFrameDuration = frameDuration
    device.activeVideoMaxFrameDuration = frameDuration

    return format.dimensions
  }
}

extension AVCaptureDevice.Format {

  fileprivate var dimensions: CMVideoDimensions {
    CMVideoFormatDescriptionGetDimensions(formatDescription)
  }

  /// Whether the frame fits inside `maximumDimensions` regardless of orientation. Formats are
  /// always described landscape, so a caller thinking in portrait is not refused for it.
  fileprivate func fits(within maximumDimensions: CMVideoDimensions?) -> Bool {
    guard let maximumDimensions else { return true }
    let frame = dimensions
    return max(frame.width, frame.height) <= max(maximumDimensions.width, maximumDimensions.height)
      && min(frame.width, frame.height) <= min(maximumDimensions.width, maximumDimensions.height)
  }

  /// Orders formats so the choice among equally sized ones is deliberate: unbinned over binned
  /// for sharpness, then the wider field of view, which is closest to what the preview normally
  /// shows.
  fileprivate var preferenceKey: (pixelCount: Int, unbinned: Int, fieldOfView: Float) {
    (pixelCount, isVideoBinned ? 0 : 1, videoFieldOfView)
  }

  fileprivate var pixelCount: Int {
    let dimensions = self.dimensions
    return Int(dimensions.width) * Int(dimensions.height)
  }

  fileprivate func supportsFrameRate(_ framesPerSecond: Double) -> Bool {
    frameRateRange(containing: framesPerSecond) != nil
  }

  fileprivate func frameRateRange(containing framesPerSecond: Double) -> AVFrameRateRange? {
    guard framesPerSecond > 0 else { return nil }
    return videoSupportedFrameRateRanges.first {
      $0.minFrameRate <= framesPerSecond && framesPerSecond <= $0.maxFrameRate
    }
  }

  /// The frame duration for `framesPerSecond`, or nil when no range of this format contains it.
  ///
  /// `CMTime(seconds:)` truncates, so the duration for a rate at a range's ceiling comes out a
  /// microsecond shorter than the range allows — and a duration outside the range is an
  /// exception, not an error. The range's own bounds are what AVFoundation checks against, so
  /// clamping to them is always accepted.
  fileprivate func frameDuration(for framesPerSecond: Double) -> CMTime? {
    guard let range = frameRateRange(containing: framesPerSecond) else { return nil }
    let requested = CMTime(seconds: 1 / framesPerSecond, preferredTimescale: 1_000_000)
    if CMTimeCompare(requested, range.minFrameDuration) < 0 { return range.minFrameDuration }
    if CMTimeCompare(requested, range.maxFrameDuration) > 0 { return range.maxFrameDuration }
    return requested
  }
}
