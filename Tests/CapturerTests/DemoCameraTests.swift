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
  private func makePixelBuffer(luma: UInt8, size: CGSize? = nil) throws -> CVPixelBuffer {
    let size = size ?? frameSize
    var buffer: CVPixelBuffer?
    let attributes: [String: Any] = [
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
    ]
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      Int(size.width),
      Int(size.height),
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
  private static let testFrameRate: Double = 30

  private func recordTestVideo(frameCount: Int = 12, rotationDegrees: CGFloat = 0) async throws -> URL {
    let url = temporaryURL("demo.mov")
    let recorder = DemoVideoRecorder()
    try recorder.start(to: url, size: frameSize, rotationDegrees: rotationDegrees, frameRate: Self.testFrameRate)

    for index in 0..<frameCount {
      // Wraps rather than traps past the 22nd frame; the value only needs to differ between
      // neighbouring frames.
      let buffer = try makePixelBuffer(luma: UInt8((40 + index * 10) % 256))
      let time = CMTime(value: CMTimeValue(index), timescale: 30)
      recorder.append(buffer, at: time)
    }

    return try await recorder.finish().url
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
    let tracks = try await asset.loadTracks(withMediaType: .video)
    let track = try XCTUnwrap(tracks.first, "expected a video track")
    let naturalSize = try await track.load(.naturalSize)
    XCTAssertEqual(naturalSize.width, frameSize.width)
    XCTAssertEqual(naturalSize.height, frameSize.height)
  }

  func testRecorderRefusesToFinishWithNoFrames() async throws {
    let recorder = DemoVideoRecorder()
    let url = temporaryURL("empty.mov")
    try recorder.start(to: url, size: frameSize, frameRate: Self.testFrameRate)

    do {
      _ = try await recorder.finish()
      XCTFail("finishing with no frames should throw rather than produce an unreadable file")
    } catch {
      // expected
    }
  }

  /// A repeated or earlier presentation time is accepted by the writer and then fails the whole
  /// file when it is finished. The recorder must drop that frame instead and keep the rest.
  func testRecorderDropsFramesWhoseTimeDoesNotAdvance() async throws {
    let url = temporaryURL("time.mov")
    defer { try? FileManager.default.removeItem(at: url) }
    let recorder = DemoVideoRecorder()
    try recorder.start(to: url, size: frameSize, frameRate: Self.testFrameRate)

    for index in 0..<6 {
      recorder.append(try makePixelBuffer(luma: 60), at: CMTime(value: CMTimeValue(index), timescale: 30))
    }
    // A repeat of the last time, then a step backwards, then the clock resumes.
    recorder.append(try makePixelBuffer(luma: 70), at: CMTime(value: 5, timescale: 30))
    recorder.append(try makePixelBuffer(luma: 80), at: CMTime(value: 2, timescale: 30))
    recorder.append(try makePixelBuffer(luma: 90), at: CMTime(value: 6, timescale: 30))

    let recording = try await recorder.finish()
    XCTAssertEqual(recording.frameCount, 7)
    XCTAssertEqual(recording.droppedFrames.unusableTime, 2)
    XCTAssertEqual(recording.droppedFrames.total, 2)
    XCTAssertTrue(FileManager.default.fileExists(atPath: recording.url.path))
  }

  /// The writer scales and crops a frame of the wrong size without complaint; the recorder must
  /// refuse it so the file only ever holds what the camera produced.
  func testRecorderDropsFramesOfTheWrongSize() async throws {
    let url = temporaryURL("size.mov")
    defer { try? FileManager.default.removeItem(at: url) }
    let recorder = DemoVideoRecorder()
    try recorder.start(to: url, size: frameSize, frameRate: Self.testFrameRate)

    recorder.append(try makePixelBuffer(luma: 60), at: CMTime(value: 0, timescale: 30))
    recorder.append(
      try makePixelBuffer(luma: 70, size: CGSize(width: 640, height: 480)),
      at: CMTime(value: 1, timescale: 30)
    )
    recorder.append(try makePixelBuffer(luma: 80), at: CMTime(value: 2, timescale: 30))

    let recording = try await recorder.finish()
    XCTAssertEqual(recording.frameCount, 2)
    XCTAssertEqual(recording.droppedFrames.sizeMismatch, 1)
    XCTAssertEqual(recording.droppedFrames.total, 1)
  }

  /// A non-positive rate would become a zero bit rate, which AVFoundation answers with an
  /// Objective-C exception rather than an error. It has to be refused before that point.
  func testRecorderRejectsAnUnusableFrameRate() {
    for frameRate in [0.0, -30.0, .nan, .infinity] {
      let recorder = DemoVideoRecorder()
      do {
        try recorder.start(to: temporaryURL("rate.mov"), size: frameSize, frameRate: frameRate)
        XCTFail("frame rate \(frameRate) should be refused")
      } catch DemoVideoRecorder.Error.invalidFrameRate {
        // As specified.
      } catch {
        XCTFail("frame rate \(frameRate) failed with the wrong error: \(error)")
      }
    }
  }

  /// A writer that cannot start still reports its input as ready and refuses every frame, so
  /// without checking at `start` the failure would surface at `finish` as "nothing recorded".
  func testRecorderReportsAnUnwritableDestinationAtStart() {
    let url = temporaryURL("missing-directory-\(UUID().uuidString)")
      .appendingPathComponent("demo.mov")
    let recorder = DemoVideoRecorder()
    do {
      try recorder.start(to: url, size: frameSize, frameRate: Self.testFrameRate)
      XCTFail("a destination in a missing directory should be refused at start")
    } catch DemoVideoRecorder.Error.couldNotStartWriting {
      // As specified.
    } catch DemoVideoRecorder.Error.couldNotCreateWriter {
      // Also acceptable: some releases refuse the URL at construction instead.
    } catch {
      XCTFail("wrong error: \(error)")
    }
  }

  // MARK: - Playback

  func testMissingVideoIsRejectedAtConstruction() async {
    let missing = temporaryURL("does-not-exist.mov")
    do {
      _ = try await DemoVideoSource.prepare(videoURLs: [missing])
      XCTFail("a missing video should be rejected")
    } catch DemoVideoSource.Error.videoNotFound {
      // As specified.
    } catch {
      XCTFail("expected videoNotFound, got \(error)")
    }
  }

  func testEmptyVideoListIsRejected() async {
    do {
      _ = try await DemoVideoSource.prepare(videoURLs: [])
      XCTFail("an empty list should be rejected")
    } catch DemoVideoSource.Error.noVideosAvailable {
      // As specified.
    } catch {
      XCTFail("expected noVideosAvailable, got \(error)")
    }
  }

  /// The claim under test: frames from a file reach subscribers of the camera's own bus.
  func testPlaybackPublishesFramesOntoTheCameraBus() async throws {
    let url = try await recordTestVideo()
    defer { try? FileManager.default.removeItem(at: url) }

    let output = VideoDataOutput()
    let received = Received()
    let cancellable = output.pixelBufferBus.addHandler { _ in
      Task { await received.increment() }
    }
    defer { cancellable.cancel() }

    let source = try await DemoVideoSource.prepare(videoURLs: [url])
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
    let source = try await DemoVideoSource.prepare(videoURLs: [url])
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
    photoOutput.demoSource = try await DemoVideoSource.prepare(videoURLs: [url])  // never started

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


  // MARK: - Playback pacing

  /// A consumer that stalls must not stretch the footage: the source keeps to the clock and the
  /// consumer gets the frame for now, so a slow consumer receives fewer frames, never later ones.
  func testSlowConsumerCostsDroppedFramesNotDelay() async throws {
    let url = try await recordTestVideo(frameCount: 20)
    let source = try await DemoVideoSource.prepare(videoURLs: [url])
    let output = VideoDataOutput()

    let counter = FrameCounter()
    let subscription = output.sampleBufferBus.addHandler { _ in
      counter.increment()
      // Far slower than the 30 fps the recording plays at.
      Thread.sleep(forTimeInterval: 0.1)
    }
    defer { subscription.cancel() }

    source.start(feeding: output)
    try await Task.sleep(nanoseconds: 1_500_000_000)
    source.stop()

    // A second and a half of 30 fps footage is 45 frames. A consumer that takes a tenth of a
    // second per frame can take about fifteen of them; had the rest been queued up for it, it
    // would still be working through them now.
    let received = counter.count
    XCTAssertGreaterThanOrEqual(received, 5, "playback did not run")
    XCTAssertLessThan(received, 30, "frames were queued for a consumer that could not keep up")
  }

  private final class FrameCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return _count }
    func increment() { lock.lock(); _count += 1; lock.unlock() }
  }

  /// A camera records in the sensor's landscape orientation and the preview layer is what turns
  /// the picture upright. That layer is not in this path, so the rotation has to travel with the
  /// file — otherwise every consumer downstream gets sideways frames.
  func testRecordedRotationTravelsWithTheFile() async throws {
    let url = try await recordTestVideo(rotationDegrees: 90)
    defer { try? FileManager.default.removeItem(at: url) }

    let tracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .video)
    let track = try XCTUnwrap(tracks.first)
    let (naturalSize, preferredTransform) = try await track.load(.naturalSize, .preferredTransform)
    XCTAssertFalse(
      preferredTransform.isIdentity,
      "a recording made with a rotation should carry it, not lose it"
    )
    // A quarter turn swaps what the track reports as its display size.
    let displaySize = naturalSize.applying(preferredTransform)
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
    let source = try await DemoVideoSource.prepare(videoURLs: [url])
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
    let source = try await DemoVideoSource.prepare(videoURLs: [url])
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
    let source = try await DemoVideoSource.prepare(videoURLs: [url])
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
    XCTAssertEqual(PreviewOutput.rotationNeeded(horizonAngle: 90, connectionAngle: 0), 90,
                   "connection refused rotation: the whole horizon angle is still owed")
    XCTAssertEqual(PreviewOutput.rotationNeeded(horizonAngle: 90, connectionAngle: 90), 0,
                   "connection already rotated the frames: nothing is owed, or they turn twice")
    XCTAssertEqual(PreviewOutput.rotationNeeded(horizonAngle: 270, connectionAngle: 90), 180)
    XCTAssertEqual(PreviewOutput.rotationNeeded(horizonAngle: 0, connectionAngle: 0), 0)
  }

  func testRotationNeededNormalisesBelowZeroAndAboveAFullTurn() {
    XCTAssertEqual(PreviewOutput.rotationNeeded(horizonAngle: 0, connectionAngle: 90), 270,
                   "a negative remainder wraps to the equivalent positive turn")
    XCTAssertEqual(PreviewOutput.rotationNeeded(horizonAngle: 450, connectionAngle: 0), 90)
    XCTAssertEqual(PreviewOutput.rotationNeeded(horizonAngle: 360, connectionAngle: 0), 0)
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
