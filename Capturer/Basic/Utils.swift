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

  /// Wraps a bare pixel buffer the way a capture output would have delivered it.
  ///
  /// Anything that feeds frames onto the buses from somewhere other than a capture session needs
  /// the same shape a session produces: an image buffer with a format description and a
  /// presentation time. The duration is left unset, as it is on frames from
  /// `AVCaptureVideoDataOutput`.
  static func wrapping(imageBuffer: CVPixelBuffer, presentationTime: CMTime) throws -> CMSampleBuffer {
    let formatDescription = try CMVideoFormatDescription(imageBuffer: imageBuffer)
    let timing = CMSampleTimingInfo(
      duration: .invalid,
      presentationTimeStamp: presentationTime,
      decodeTimeStamp: .invalid
    )
    return try CMSampleBuffer(
      imageBuffer: imageBuffer,
      formatDescription: formatDescription,
      sampleTiming: timing
    )
  }
}

/// A single slot that holds the newest value put into it.
///
/// The hand-off for anything that must keep up with a stream it cannot always match — a view
/// drawing frames on main, a converter on its own queue. `replace(with:)` says whether the slot
/// was empty, which is the caller's cue to schedule one consumer; a value put into an occupied
/// slot replaces the one that was waiting, and the consumer already on its way takes the newer
/// one. So at most one consumer is ever pending, and the value it gets is always the latest.
final class LatestValueSlot<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Value?

  /// Stores `newValue`, returning `true` when nothing was waiting before — the signal to
  /// schedule a consumer. Returns `false` when a consumer is already on its way.
  func replace(with newValue: Value) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    let wasEmpty = value == nil
    value = newValue
    return wasEmpty
  }

  /// Removes and returns whatever is waiting.
  func take() -> Value? {
    lock.lock()
    defer { lock.unlock() }
    let taken = value
    value = nil
    return taken
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
