@preconcurrency import AVFoundation
import CoreGraphics
import Foundation

/// What a captured photo has to be able to do, independent of where it came from.
///
/// `AVCapturePhoto` cannot be constructed — it has no public initialiser, and only AVFoundation
/// ever makes one. That is fine while every photo comes from a camera, and a hard wall as soon as
/// frames come from somewhere else: a recorded video standing in for a camera on the simulator,
/// a fixture image in a test, a synthesised frame.
///
/// The three members below are the entire surface anything actually uses of a captured photo —
/// `CapturePhoto.orientation` reads `metadata`, `CapturePhoto.makeImage(isMirrored:)` calls
/// `cgImageRepresentation()`, and both apps call `fileDataRepresentation()` on the way to a
/// `UIImage`. Naming that surface lets a non-camera photo satisfy it without anything downstream
/// knowing, and without `CapturePhoto.photo` becoming optional or a set of cases every caller has
/// to unwrap.
public protocol CapturedPhotoRepresentable: AnyObject, Sendable {

  /// Image metadata, keyed by the `kCGImageProperty*` constants as `String`.
  ///
  /// `CapturePhoto.orientation` requires `kCGImagePropertyOrientation` to be present, so any
  /// conformance must supply it.
  var metadata: [String: Any] { get }

  /// The photo as a `CGImage`, or `nil` if it cannot be represented as one.
  func cgImageRepresentation() -> CGImage?

  /// The photo encoded as a file, ready to be written or handed to `UIImage(data:)`.
  func fileDataRepresentation() -> Data?
}

/// The camera's own photo already does all three; there is nothing to add.
extension AVCapturePhoto: CapturedPhotoRepresentable {}
