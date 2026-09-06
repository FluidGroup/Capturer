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
///
/// `@unchecked Sendable` because every access is under the lock; the value itself crosses
/// threads by design — a `CVPixelBuffer` from a delivery thread to main — and is not required
/// to be `Sendable`.
public final class LatestValueSlot<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Value?

  public init() {}

  /// Stores `newValue`, returning `true` when nothing was waiting before — the signal to
  /// schedule a consumer. Returns `false` when a consumer is already on its way.
  ///
  /// The consumer that is scheduled must call `take()` exactly once, and before anything that
  /// could return early: the slot stays occupied until it does, and while it is occupied no
  /// further consumer is ever scheduled. `take()` returns `nil` only if that was not honoured.
  public func replace(with newValue: Value) -> Bool {
    lock.lock()
    let previous = value
    value = newValue
    lock.unlock()
    // The displaced value is released here, after the lock, so a consumer waiting in `take()`
    // is not held up by whatever freeing it costs.
    return withExtendedLifetime(previous) { previous == nil }
  }

  /// Removes and returns whatever is waiting.
  public func take() -> Value? {
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
      "videoRotationAngle": videoRotationAngle,
      "isVideoMirrored" : isVideoMirrored,
      "automaticallyAdjustsVideoMirroring" : automaticallyAdjustsVideoMirroring,
      "inputPorts" : inputPorts
    ]
  }

}
