import AVFoundation
import CoreMedia
import XCTest

@testable import Capturer

/// Exercises the pieces that let recorded video stand in for a camera.
///
/// The round trip matters more than any single piece: frames are recorded through
/// `DemoVideoRecorder`, read back by `DemoVideoSource`, published onto the same bus the camera
/// publishes onto, and captured through `PhotoOutput`. If that whole path works, an app using
/// Capturer cannot tell a recording from a camera — which is the entire claim being made.
final class DemoCameraTests: XCTestCase {

  private let frameSize = CGSize(width: 320, height: 240)

  // MARK: - Helpers

  /// A solid-colour frame, so a test can tell one frame from another by reading a pixel.
  private func makePixelBuffer(luma: UInt8) throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    let attributes: [String: Any] = [
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
    ]
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      Int(frameSize.width),
      Int(frameSize.height),
      kCVPixelFormatType_32BGRA,
      attributes as CFDictionary,
      &buffer
    )
    let pixelBuffer = try XCTUnwrap(buffer, "CVPixelBufferCreate failed with status \(status)")

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
    let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixelBuffer))
    let bytes = CVPixelBufferGetBytesPerRow(pixelBuffer) * CVPixelBufferGetHeight(pixelBuffer)
    memset(base, Int32(luma), bytes)
    return pixelBuffer
  }

  private func temporaryURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("CapturerTests-\(UUID().uuidString)-\(name)")
  }

  /// Writes a short video of solid frames and returns where it landed.
  private func recordTestVideo(frameCount: Int = 12) async throws -> URL {
    let url = temporaryURL("demo.mov")
    let recorder = DemoVideoRecorder()
    try recorder.start(to: url, size: frameSize)

    for index in 0..<frameCount {
      let buffer = try makePixelBuffer(luma: UInt8(40 + index * 10))
      let time = CMTime(value: CMTimeValue(index), timescale: 30)
      recorder.append(buffer, at: time)
    }

    return try await recorder.finish()
  }

  // MARK: - PixelBufferCapturedPhoto

  func testPixelBufferPhotoSatisfiesTheCapturedPhotoContract() throws {
    let photo = PixelBufferCapturedPhoto(pixelBuffer: try makePixelBuffer(luma: 120))

    let cgImage = try XCTUnwrap(photo.cgImageRepresentation(), "should render a CGImage")
    XCTAssertEqual(cgImage.width, Int(frameSize.width))
    XCTAssertEqual(cgImage.height, Int(frameSize.height))

    let data = try XCTUnwrap(photo.fileDataRepresentation(), "should encode to file data")
    XCTAssertGreaterThan(data.count, 0)
    // A JPEG, so anything reading this the way an app reads a camera photo succeeds.
    XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xD8], "expected a JPEG SOI marker")
  }

  func testCapturedPhotoOrientationComesFromMetadata() throws {
    let photo = PixelBufferCapturedPhoto(
      pixelBuffer: try makePixelBuffer(luma: 90),
      orientation: .right
    )
    let capture = PhotoOutput.CapturePhoto(photo: photo)
    XCTAssertEqual(capture.orientation, .right)
  }

  /// A conformance missing the orientation key must degrade, not crash — the previous code
  /// force-unwrapped it, which was survivable only because AVFoundation always sets it.
  func testCapturedPhotoOrientationFallsBackRatherThanTrapping() {
    final class NoMetadataPhoto: CapturedPhotoRepresentable, @unchecked Sendable {
      let metadata: [String: Any] = [:]
      func cgImageRepresentation() -> CGImage? { nil }
      func fileDataRepresentation() -> Data? { nil }
    }
    let capture = PhotoOutput.CapturePhoto(photo: NoMetadataPhoto())
    XCTAssertEqual(capture.orientation, .up)
    XCTAssertNil(capture.makeImage(isMirrored: false))
  }

  // MARK: - Recording

  func testRecorderWritesAReadableVideo() async throws {
    let url = try await recordTestVideo()
    defer { try? FileManager.default.removeItem(at: url) }

    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

    let asset = AVURLAsset(url: url)
    let track = try XCTUnwrap(asset.tracks(withMediaType: .video).first, "expected a video track")
    XCTAssertEqual(track.naturalSize.width, frameSize.width)
    XCTAssertEqual(track.naturalSize.height, frameSize.height)
  }

  func testRecorderRefusesToFinishWithNoFrames() async throws {
    let recorder = DemoVideoRecorder()
    let url = temporaryURL("empty.mov")
    try recorder.start(to: url, size: frameSize)

    do {
      _ = try await recorder.finish()
      XCTFail("finishing with no frames should throw rather than produce an unreadable file")
    } catch {
      // expected
    }
  }

  // MARK: - Playback

  func testMissingVideoIsRejectedAtConstruction() {
    let missing = temporaryURL("does-not-exist.mov")
    XCTAssertThrowsError(try DemoVideoSource(videoURLs: [missing])) { error in
      guard case DemoVideoSource.Error.videoNotFound = error else {
        return XCTFail("expected videoNotFound, got \(error)")
      }
    }
  }

  func testEmptyVideoListIsRejected() {
    XCTAssertThrowsError(try DemoVideoSource(videoURLs: [])) { error in
      guard case DemoVideoSource.Error.noVideosAvailable = error else {
        return XCTFail("expected noVideosAvailable, got \(error)")
      }
    }
  }

  /// The claim under test: frames from a file reach subscribers of the camera's own bus.
  func testPlaybackPublishesFramesOntoTheCameraBus() async throws {
    let url = try await recordTestVideo()
    defer { try? FileManager.default.removeItem(at: url) }

    let output = VideoDataOutput()
    let received = Received()
    let cancellable = await output.pixelBufferBus.addHandler { _ in
      Task { await received.increment() }
    }
    defer { cancellable.cancel() }

    let source = try DemoVideoSource(videoURLs: [url])
    source.start(feeding: output)
    defer { source.stop() }

    try await waitUntil("frames arrive on the pixel buffer bus") {
      await received.count > 0
    }

    let latest = source.latestPixelBuffer
    XCTAssertNotNil(latest, "the source should expose the frame it last published")
  }

  /// The whole point: a capture with a demo source behaves like a capture with a camera.
  func testCaptureWithADemoSourceReturnsThePhotoOnScreen() async throws {
    let url = try await recordTestVideo()
    defer { try? FileManager.default.removeItem(at: url) }

    let output = VideoDataOutput()
    let source = try DemoVideoSource(videoURLs: [url])
    source.start(feeding: output)
    defer { source.stop() }

    try await waitUntil("the source has a frame to capture") {
      source.latestPixelBuffer != nil
    }

    let photoOutput = PhotoOutput()
    photoOutput.demoSource = source

    let captured = try await photoOutput.capture(with: AVCapturePhotoSettings())
    let data = try XCTUnwrap(
      captured.photo.fileDataRepresentation(),
      "an app reads a captured photo exactly this way, whatever produced it"
    )
    XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xD8], "expected a JPEG")
  }

  func testCaptureWithoutAFrameYetReportsRatherThanHanging() async throws {
    let url = try await recordTestVideo()
    defer { try? FileManager.default.removeItem(at: url) }

    let photoOutput = PhotoOutput()
    photoOutput.demoSource = try DemoVideoSource(videoURLs: [url])  // never started

    do {
      _ = try await photoOutput.capture(with: AVCapturePhotoSettings())
      XCTFail("capturing before any frame exists should fail, not return an empty photo")
    } catch PhotoOutput.CaptureError.noFrameAvailable {
      // expected
    }
  }

  // MARK: - Test support

  private actor Received {
    var count = 0
    func increment() { count += 1 }
  }

  private func waitUntil(
    _ description: String,
    timeout: TimeInterval = 5,
    _ condition: @escaping () async -> Bool
  ) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if await condition() { return }
      try await Task.sleep(nanoseconds: 50_000_000)
    }
    XCTFail("timed out waiting for: \(description)")
  }
}
