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
  private func recordTestVideo(frameCount: Int = 12, rotationDegrees: CGFloat = 0) async throws -> URL {
    let url = temporaryURL("demo.mov")
    let recorder = DemoVideoRecorder()
    try recorder.start(to: url, size: frameSize, rotationDegrees: rotationDegrees)

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

  // MARK: - Orientation

  /// A camera records in the sensor's landscape orientation and the preview layer is what turns
  /// the picture upright. That layer is not in this path, so the rotation has to travel with the
  /// file — otherwise every consumer downstream gets sideways frames.
  func testRecordedRotationTravelsWithTheFile() async throws {
    let url = try await recordTestVideo(rotationDegrees: 90)
    defer { try? FileManager.default.removeItem(at: url) }

    let track = try XCTUnwrap(AVURLAsset(url: url).tracks(withMediaType: .video).first)
    XCTAssertFalse(
      track.preferredTransform.isIdentity,
      "a recording made with a rotation should carry it, not lose it"
    )
    // A quarter turn swaps what the track reports as its display size.
    let displaySize = track.naturalSize.applying(track.preferredTransform)
    XCTAssertEqual(abs(displaySize.width), frameSize.height, accuracy: 1)
    XCTAssertEqual(abs(displaySize.height), frameSize.width, accuracy: 1)
  }

  /// The rotation has to reach the *buffers*, not just the file's metadata. The shutter returns
  /// the buffer rather than anything the preview did with it, so a fix that only turned the
  /// preview upright would still photograph the scene sideways.
  func testPlaybackTurnsRotatedFootageUprightForEveryConsumer() async throws {
    let url = try await recordTestVideo(rotationDegrees: 90)
    defer { try? FileManager.default.removeItem(at: url) }

    let output = VideoDataOutput()
    let source = try DemoVideoSource(videoURLs: [url])
    source.start(feeding: output)
    defer { source.stop() }

    try await waitUntil("a frame is published") { source.latestPixelBuffer != nil }
    let frame = try XCTUnwrap(source.latestPixelBuffer)

    XCTAssertEqual(CVPixelBufferGetWidth(frame), Int(frameSize.height),
                   "a quarter turn should swap the frame's width and height")
    XCTAssertEqual(CVPixelBufferGetHeight(frame), Int(frameSize.width),
                   "a quarter turn should swap the frame's width and height")
    XCTAssertEqual(source.naturalSize.width, frameSize.height, accuracy: 1,
                   "naturalSize should describe the frames handed out, not the stored track")
    XCTAssertEqual(source.naturalSize.height, frameSize.width, accuracy: 1,
                   "naturalSize should describe the frames handed out, not the stored track")
  }

  /// Footage recorded without a rotation must come back untouched — the composition is there to
  /// honour what the file says, not to impose a turn of its own.
  func testPlaybackLeavesUnrotatedFootageAlone() async throws {
    let url = try await recordTestVideo()
    defer { try? FileManager.default.removeItem(at: url) }

    let output = VideoDataOutput()
    let source = try DemoVideoSource(videoURLs: [url])
    source.start(feeding: output)
    defer { source.stop() }

    try await waitUntil("a frame is published") { source.latestPixelBuffer != nil }
    let frame = try XCTUnwrap(source.latestPixelBuffer)

    XCTAssertEqual(CVPixelBufferGetWidth(frame), Int(frameSize.width))
    XCTAssertEqual(CVPixelBufferGetHeight(frame), Int(frameSize.height))
  }

  /// Rotated frames must still be IOSurface-backed. Losing that backing is the failure that
  /// showed nothing at all on screen, with the frames arriving correctly the entire time.
  func testRotatedFramesAreStillIOSurfaceBacked() async throws {
    let url = try await recordTestVideo(rotationDegrees: 90)
    defer { try? FileManager.default.removeItem(at: url) }

    let output = VideoDataOutput()
    let source = try DemoVideoSource(videoURLs: [url])
    source.start(feeding: output)
    defer { source.stop() }

    try await waitUntil("a frame is published") { source.latestPixelBuffer != nil }
    let frame = try XCTUnwrap(source.latestPixelBuffer)
    XCTAssertNotNil(CVPixelBufferGetIOSurface(frame),
                    "the preview draws these as layer contents, which needs an IOSurface")
  }

  // MARK: - Rotation still needed

  /// The recorder must stamp only what the connection did *not* already apply. A device whose
  /// data connection refuses rotation hands over sensor-landscape frames and reports zero; one
  /// whose connection rotates them reports the full angle and the frames are already upright.
  func testRotationNeededIsTheDifferenceBetweenHorizonAndConnection() {
    XCTAssertEqual(PreviewOutput.rotationNeeded(previewAngle: 90, connectionAngle: 0), 90,
                   "connection refused rotation: the whole horizon angle is still owed")
    XCTAssertEqual(PreviewOutput.rotationNeeded(previewAngle: 90, connectionAngle: 90), 0,
                   "connection already rotated the frames: nothing is owed, or they turn twice")
    XCTAssertEqual(PreviewOutput.rotationNeeded(previewAngle: 270, connectionAngle: 90), 180)
    XCTAssertEqual(PreviewOutput.rotationNeeded(previewAngle: 0, connectionAngle: 0), 0)
  }

  func testRotationNeededNormalisesBelowZeroAndAboveAFullTurn() {
    XCTAssertEqual(PreviewOutput.rotationNeeded(previewAngle: 0, connectionAngle: 90), 270,
                   "a negative remainder wraps to the equivalent positive turn")
    XCTAssertEqual(PreviewOutput.rotationNeeded(previewAngle: 450, connectionAngle: 0), 90)
    XCTAssertEqual(PreviewOutput.rotationNeeded(previewAngle: 360, connectionAngle: 0), 0)
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
