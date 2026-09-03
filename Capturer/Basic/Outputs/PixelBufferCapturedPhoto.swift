@preconcurrency import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A captured photo made from a pixel buffer rather than by a camera.
///
/// This is what lets a capture succeed when the frames are not coming from a camera at all — a
/// recorded video standing in on the simulator, or a fixture in a test. It satisfies the same
/// contract as `AVCapturePhoto`, so `PhotoOutput.CapturePhoto` and everything downstream cannot
/// tell the difference.
///
/// Encoding happens once, on first use, because a caller typically wants either the `CGImage` or
/// the file data and rarely both, and the JPEG encode is the expensive part.
public final class PixelBufferCapturedPhoto: CapturedPhotoRepresentable, @unchecked Sendable {

  public let metadata: [String: Any]

  private let lock = NSLock()
  private let sourceImage: CGImage?
  private var encodedData: Data?
  private var hasEncoded = false

  /// - Parameters:
  ///   - pixelBuffer: The frame to capture. Converted immediately, so the buffer may be reused by
  ///     its producer as soon as this returns.
  ///   - orientation: Recorded under `kCGImagePropertyOrientation`, exactly where
  ///     `CapturePhoto.orientation` looks for it.
  public init(
    pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation = .up,
    context: CIContext = CIContext()
  ) {
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    self.sourceImage = context.createCGImage(ciImage, from: ciImage.extent)
    self.metadata = [
      String(kCGImagePropertyOrientation): NSNumber(value: orientation.rawValue)
    ]
  }

  public func cgImageRepresentation() -> CGImage? {
    sourceImage
  }

  public func fileDataRepresentation() -> Data? {
    lock.lock()
    defer { lock.unlock() }

    if hasEncoded {
      return encodedData
    }
    hasEncoded = true

    guard let sourceImage else {
      return nil
    }

    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data, UTType.jpeg.identifier as CFString, 1, nil
      )
    else {
      return nil
    }
    // Carry the orientation into the file, so a reader that honours EXIF sees what
    // `CapturePhoto.orientation` reports.
    CGImageDestinationAddImage(destination, sourceImage, metadata as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      return nil
    }
    encodedData = data as Data
    return encodedData
  }
}
