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
  ///
  /// - Parameter shade: When set, every frame is this one shade, so a decoded frame can say
  ///   which video it came from. When `nil`, neighbouring frames differ.
  private static let testFrameRate: Double = 30

  private func recordTestVideo(
    frameCount: Int = 12,
    rotationDegrees: CGFloat = 0,
    shade: UInt8? = nil
  ) async throws -> URL {
    let url = temporaryURL("demo.mov")
    let recorder = DemoVideoRecorder()
    try recorder.start(to: url, size: frameSize, rotationDegrees: rotationDegrees, frameRate: Self.testFrameRate)

    for index in 0..<frameCount {
      // Wraps rather than traps past the 22nd frame; the value only needs to differ between
      // neighbouring frames.
      let buffer = try makePixelBuffer(luma: shade ?? UInt8((40 + index * 10) % 256))
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

  /// The recording overlay in an app can call these in any order; every misuse must be an error
  /// or a dropped frame, never an `AVAssetWriter` exception. A second `start` in particular must
  /// be refused *before* the file is removed, or it would delete the recording in progress.
  func testRecorderRejectsMisuseInsteadOfRaising() async throws {
    let url = temporaryURL("misuse.mov")
    defer { try? FileManager.default.removeItem(at: url) }
    let recorder = DemoVideoRecorder()

    recorder.append(try makePixelBuffer(luma: 1), at: .zero)  // before start: dropped

    try recorder.start(to: url, size: frameSize, frameRate: Self.testFrameRate)
    XCTAssertThrowsError(try recorder.start(to: url, size: frameSize, frameRate: Self.testFrameRate), "a second start must be refused")
    for index in 0..<3 {
      recorder.append(try makePixelBuffer(luma: 2), at: CMTime(value: CMTimeValue(index), timescale: 30))
    }
    let finished = try await recorder.finish()
    XCTAssertEqual(finished.url, url)
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "the refused second start removed the file")

    recorder.append(try makePixelBuffer(luma: 3), at: CMTime(value: 3, timescale: 30))  // after finish: dropped
    do {
      _ = try await recorder.finish()
      XCTFail("a second finish should throw")
    } catch DemoVideoRecorder.Error.nothingRecorded {
      // expected
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

  /// A file that is not a video must fail at `prepare`, not produce a source that never
  /// publishes. AVFoundation reports an unparseable file by throwing from `loadTracks`, and that
  /// error does not say which file; `prepare` must, because the caller may have given several.
  func testAFileThatIsNotAVideoIsRejectedByPrepareNamingTheFile() async throws {
    let url = temporaryURL("not-a-video.mov")
    try Data("not a video".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    do {
      _ = try await DemoVideoSource.prepare(videoURLs: [url])
      XCTFail("a file that is not a video should be rejected")
    } catch DemoVideoSource.Error.couldNotReadVideo(let reported, underlying: let underlying) {
      XCTAssertEqual(reported, url)
      // Which AVError code says "not a video" differs between OS releases; that it is
      // AVFoundation's own error, carried through, is the contract.
      XCTAssertTrue(underlying is AVError, "unexpected underlying error: \(underlying)")
    } catch {
      XCTFail("expected couldNotReadVideo, got \(error)")
    }
  }

  func testNaturalSizeBeforeStartDescribesTheFirstVideoAfterItsRotation() async throws {
    let url = try await recordTestVideo(rotationDegrees: 90)
    defer { try? FileManager.default.removeItem(at: url) }

    let source = try await DemoVideoSource.prepare(videoURLs: [url])
    XCTAssertEqual(source.naturalSize.width, frameSize.height, accuracy: 1)
    XCTAssertEqual(source.naturalSize.height, frameSize.width, accuracy: 1)
    XCTAssertNil(source.latestPixelBuffer, "nothing has been published before start")
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

  // MARK: - Looping

  /// Which of `shades` a decoded frame is — read from the green channel at the centre. H.264
  /// shifts a solid grey by a few levels; the shades are 88 apart, so nearest-match is safe.
  private static func videoIndex(of buffer: CVPixelBuffer, shades: [UInt8]) -> Int? {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else {
      return nil
    }
    let row = CVPixelBufferGetHeight(buffer) / 2
    let column = CVPixelBufferGetWidth(buffer) / 2
    let green = Int(base[row * CVPixelBufferGetBytesPerRow(buffer) + column * 4 + 1])
    let nearest = shades.enumerated()
      .map { (index: $0.offset, distance: abs(Int($0.element) - green)) }
      .min { $0.distance < $1.distance }
    guard let nearest, nearest.distance <= 44 else { return nil }
    return nearest.index
  }

  /// Collapses per-frame video indices into the sequence of videos played. Runs shorter than
  /// three frames are ignored: at a hand-over both queued items are asked for a frame, and a
  /// single stray frame from the item just finished is not a playback-order fault.
  private static func playbackOrder(of indices: [Int]) -> [Int] {
    var runs: [(index: Int, length: Int)] = []
    for index in indices {
      if let last = runs.last, last.index == index {
        runs[runs.count - 1].length += 1
      } else {
        runs.append((index, 1))
      }
    }
    var order: [Int] = []
    for run in runs where run.length >= 3 {
      if order.last != run.index {
        order.append(run.index)
      }
    }
    return order
  }

  /// The hand-over path — `AVQueuePlayer` with two items queued, `videoDidEnd` enqueueing the
  /// next, the index wrapping — never runs with a single video. Three videos, each a solid shade
  /// so every frame says which video it came from, the last recorded a quarter turn round so
  /// each video's own rotation is checked across the hand-over. The presentation times must
  /// keep climbing across hand-overs too: item time restarts at zero on every item, and a
  /// consumer such as `DemoVideoRecorder` subtracts a start time from them.
  func testThreeVideosLoopInOrderWithTheirOwnRotationAndClimbingTimestamps() async throws {
    let shades: [UInt8] = [40, 128, 216]
    let count = shades.count
    var recorded: [URL] = []
    for index in 0..<count {
      recorded.append(try await recordTestVideo(
        frameCount: 30,
        rotationDegrees: index == count - 1 ? 90 : 0,
        shade: shades[index]
      ))
    }
    let urls = recorded
    defer { for url in urls { try? FileManager.default.removeItem(at: url) } }

    let upright = frameSize
    let turned = CGSize(width: frameSize.height, height: frameSize.width)
    let output = VideoDataOutput()
    let seen = SynchronizedList<Int>()
    let wrongSize = FrameCounter()
    let presentationTimes = SynchronizedList<Double>()
    let pixelSubscription = output.pixelBufferBus.addHandler { buffer in
      let index = Self.videoIndex(of: buffer, shades: shades)
      seen.append(index ?? -1)
      guard let index else { return }
      let expected = index == count - 1 ? turned : upright
      if CVPixelBufferGetWidth(buffer) != Int(expected.width)
          || CVPixelBufferGetHeight(buffer) != Int(expected.height) {
        wrongSize.increment()
      }
    }
    let sampleSubscription = output.sampleBufferBus.addHandler { sample in
      presentationTimes.append(sample.presentationTimeStamp.seconds)
    }
    defer {
      pixelSubscription.cancel()
      sampleSubscription.cancel()
    }

    let source = try await DemoVideoSource.prepare(videoURLs: urls)
    source.start(feeding: output)
    defer { source.stop() }

    // A second per video; the first must come round again after the last.
    try await waitUntil("every video plays and the first comes round again", timeout: 30) {
      Self.playbackOrder(of: seen.snapshot).count >= count + 1
    }

    let frames = seen.snapshot
    let order = Self.playbackOrder(of: frames)
    XCTAssertFalse(frames.contains(-1), "a frame matched none of the videos")
    XCTAssertEqual(order.first, 0, "playback should begin with the first video: \(order)")
    for (previous, next) in zip(order, order.dropFirst()) {
      XCTAssertEqual(next, (previous + 1) % count, "videos played out of order: \(order)")
    }
    XCTAssertEqual(wrongSize.count, 0, "a frame's size did not match its own video's rotation")

    let times = presentationTimes.snapshot
    XCTAssertGreaterThan(times.count, 1)
    XCTAssertTrue(
      zip(times, times.dropFirst()).allSatisfy { $0 < $1 },
      "presentation times must climb across loops and hand-overs, as a capture session's do"
    )
  }

  // MARK: - Start / stop

  func testStopEndsFramesAndStartResumesThem() async throws {
    let url = try await recordTestVideo(frameCount: 30)
    defer { try? FileManager.default.removeItem(at: url) }

    let output = VideoDataOutput()
    let counter = FrameCounter()
    let subscription = output.pixelBufferBus.addHandler { _ in counter.increment() }
    defer { subscription.cancel() }
    let source = try await DemoVideoSource.prepare(videoURLs: [url])

    source.start(feeding: output)
    source.start(feeding: output)  // a second start is a no-op, not a second player
    try await waitUntil("frames flow") { counter.count >= 3 }

    source.stop()
    source.stop()
    // One frame may already be on its way through a handler when stop() returns; after it, none.
    try await Task.sleep(nanoseconds: 300_000_000)
    let afterStop = counter.count
    try await Task.sleep(nanoseconds: 700_000_000)
    XCTAssertEqual(counter.count, afterStop, "frames kept arriving after stop()")

    source.start(feeding: output)
    defer { source.stop() }
    try await waitUntil("frames flow again") { counter.count >= afterStop + 3 }
  }

  /// `stop()` is called from the app's main thread. A handler stuck mid-frame is on the frame
  /// thread, and stopping must not wait for it — the producer is the one that waits on
  /// handlers, never the other way round.
  func testStopDoesNotWaitForABusyHandler() async throws {
    let url = try await recordTestVideo(frameCount: 30)
    defer { try? FileManager.default.removeItem(at: url) }

    let output = VideoDataOutput()
    let counter = FrameCounter()
    let subscription = output.sampleBufferBus.addHandler { _ in
      counter.increment()
      Thread.sleep(forTimeInterval: 1.0)
    }
    defer { subscription.cancel() }
    let source = try await DemoVideoSource.prepare(videoURLs: [url])
    source.start(feeding: output)
    try await waitUntil("a handler is busy") { counter.count >= 1 }

    let began = Date()
    source.stop()
    XCTAssertLessThan(Date().timeIntervalSince(began), 0.5, "stop() waited on the handler")

    // The handler in flight finishes its second; nothing may follow it.
    try await Task.sleep(nanoseconds: 1_500_000_000)
    let settled = counter.count
    try await Task.sleep(nanoseconds: 500_000_000)
    XCTAssertEqual(counter.count, settled, "frames kept arriving after stop()")
  }

  /// `FrameThread.stop` can run before `main` has recorded its run loop; either order must end
  /// the thread, and the source must still work afterwards.
  func testRapidStartStopLeavesTheSourceUsable() async throws {
    let url = try await recordTestVideo()
    defer { try? FileManager.default.removeItem(at: url) }

    let output = VideoDataOutput()
    let counter = FrameCounter()
    let subscription = output.pixelBufferBus.addHandler { _ in counter.increment() }
    defer { subscription.cancel() }
    let source = try await DemoVideoSource.prepare(videoURLs: [url])

    for _ in 0..<10 {
      source.start(feeding: output)
      source.stop()
    }
    source.start(feeding: output)
    defer { source.stop() }
    try await waitUntil("frames flow after rapid start/stop") { counter.count >= 3 }
  }

  // MARK: - Playback pacing

  /// A consumer that stalls must not stretch the footage: the source keeps to the clock and the
  /// consumer gets the frame for now, so a slow consumer receives fewer frames, never later ones.
  /// The count is compared after playback stops: a design that queued frames behind the slow
  /// handler would still be working through them.
  func testSlowConsumerCostsDroppedFramesNotDelay() async throws {
    let url = try await recordTestVideo(frameCount: 30)
    defer { try? FileManager.default.removeItem(at: url) }

    let output = VideoDataOutput()
    let counter = FrameCounter()
    let subscription = output.sampleBufferBus.addHandler { _ in
      counter.increment()
      // Far slower than the 30 fps the recording plays at.
      Thread.sleep(forTimeInterval: 0.1)
    }
    defer { subscription.cancel() }
    let source = try await DemoVideoSource.prepare(videoURLs: [url])

    source.start(feeding: output)
    try await waitUntil("the slow consumer receives frames") { counter.count >= 3 }
    source.stop()

    // The handler in flight finishes its tenth of a second; a backlog would keep delivering.
    try await Task.sleep(nanoseconds: 300_000_000)
    let afterStop = counter.count
    try await Task.sleep(nanoseconds: 700_000_000)
    XCTAssertEqual(counter.count, afterStop, "frames were queued for a consumer that could not keep up")
  }

  // MARK: - Orientation

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

  // MARK: - EventBus

  func testHandlersRunInOrderOnTheEmittingThreadBeforeEmitReturns() {
    let bus = EventBus<Int>()
    let order = SynchronizedList<String>()
    let threads = SynchronizedList<mach_port_t>()
    let first = bus.addHandler { _ in
      order.append("first")
      threads.append(Self.currentThreadID())
    }
    let second = bus.addHandler { _ in order.append("second") }
    defer {
      first.cancel()
      second.cancel()
    }

    bus.emit(element: 1)

    XCTAssertEqual(order.snapshot, ["first", "second"], "delivery must be complete, in order, when emit returns")
    XCTAssertEqual(threads.snapshot, [Self.currentThreadID()], "handlers run on the emitting thread")
  }

  func testHasTargetsFollowsAddAndCancelAndCancelIsIdempotent() {
    let bus = EventBus<Int>()
    XCTAssertFalse(bus.hasTargets)
    let first = bus.addHandler { _ in }
    let second = bus.addHandler { _ in }
    XCTAssertTrue(bus.hasTargets)
    first.cancel()
    XCTAssertTrue(bus.hasTargets)
    second.cancel()
    XCTAssertFalse(bus.hasTargets)
    second.cancel()
    XCTAssertFalse(bus.hasTargets)
  }

  /// `PixelBufferView.attach` cancels a previous subscription, and `AnyCVPixelBufferOutput`
  /// cancels from `deinit`, while frames may be in flight. The lock is not recursive: this only
  /// works because handlers run outside it, and a tidy-up that held it through the loop would
  /// deadlock the camera's delegate queue.
  func testAHandlerMayCancelAnotherOrItselfDuringEmit() {
    let bus = EventBus<Int>()
    let received = SynchronizedList<Int>()
    let victim = SynchronizedValue<EventBusCancellable>()
    let selfCancelling = SynchronizedValue<EventBusCancellable>()
    let canceller = bus.addHandler { _ in victim.value?.cancel() }
    victim.value = bus.addHandler { received.append($0) }
    selfCancelling.value = bus.addHandler { _ in selfCancelling.value?.cancel() }
    defer { canceller.cancel() }

    assertFinishes {
      bus.emit(element: 1)
      bus.emit(element: 2)
    }

    // Contract: the element being emitted may still arrive; nothing after it does.
    XCTAssertFalse(received.snapshot.contains(2), "a cancelled handler received a later element")
    XCTAssertLessThanOrEqual(received.snapshot.count, 1)
    XCTAssertTrue(bus.hasTargets, "the canceller itself is still subscribed")
  }

  func testAHandlerAddedDuringEmitSeesOnlyLaterElements() {
    let bus = EventBus<Int>()
    let late = SynchronizedList<Int>()
    let lateCancellable = SynchronizedValue<EventBusCancellable>()
    let adder = bus.addHandler { element in
      guard element == 1, lateCancellable.value == nil else { return }
      lateCancellable.value = bus.addHandler { late.append($0) }
    }
    defer {
      adder.cancel()
      lateCancellable.value?.cancel()
    }

    assertFinishes {
      bus.emit(element: 1)
      bus.emit(element: 2)
    }

    XCTAssertEqual(late.snapshot, [2])
  }

  func testCancellingAfterTheBusIsGoneIsHarmless() {
    var bus: EventBus<Int>? = EventBus()
    let cancellable = bus?.addHandler { _ in }
    bus = nil
    cancellable?.cancel()
  }

  /// Adds and cancels race a continuous emit. Meaningful under Thread Sanitizer; without it,
  /// still the test that crashes if the target list is ever read while being mutated.
  func testConcurrentAddCancelAndEmitDoNotRace() {
    let bus = EventBus<Int>()
    let group = DispatchGroup()
    let queue = DispatchQueue(label: "CapturerTests.bus-stress", attributes: .concurrent)
    for _ in 0..<4 {
      queue.async(group: group) {
        for _ in 0..<2_000 {
          bus.addHandler { _ in }.cancel()
        }
      }
    }
    queue.async(group: group) {
      for index in 0..<10_000 {
        bus.emit(element: index)
      }
    }
    XCTAssertEqual(group.wait(timeout: .now() + 20), .success, "the stress run did not finish")
    XCTAssertFalse(bus.hasTargets)
  }

  // MARK: - VideoDataOutput.emit

  func testEmitHandsTheSameFrameToBothBusesSampleBusFirstBeforeReturning() throws {
    let output = VideoDataOutput()
    let pixelBuffer = try makePixelBuffer(luma: 77)
    let sample = try CMSampleBuffer.wrapping(
      imageBuffer: pixelBuffer,
      presentationTime: CMTime(value: 3, timescale: 30)
    )
    let order = SynchronizedList<String>()
    let isSameFrame = SynchronizedList<Bool>()
    let sampleSubscription = output.sampleBufferBus.addHandler { frame in
      order.append("sample")
      isSameFrame.append(frame.imageBuffer === pixelBuffer)
    }
    let pixelSubscription = output.pixelBufferBus.addHandler { frame in
      order.append("pixel")
      isSameFrame.append(frame === pixelBuffer)
    }
    defer {
      sampleSubscription.cancel()
      pixelSubscription.cancel()
    }

    output.emit(sampleBuffer: sample)

    XCTAssertEqual(order.snapshot, ["sample", "pixel"])
    XCTAssertEqual(isSameFrame.snapshot, [true, true], "no copy: the shutter and the preview must see the same buffer")
  }

  /// Replaced a force-unwrap. A frame from anywhere but a camera has no image guarantee.
  func testAFrameWithoutAnImageReachesTheSampleBusOnlyAndDoesNotTrap() throws {
    let output = VideoDataOutput()
    let empty = try CMSampleBuffer(
      dataBuffer: nil,
      formatDescription: nil,
      numSamples: 0,
      sampleTimings: [],
      sampleSizes: []
    )
    let samples = FrameCounter()
    let pixels = FrameCounter()
    let sampleSubscription = output.sampleBufferBus.addHandler { _ in samples.increment() }
    let pixelSubscription = output.pixelBufferBus.addHandler { _ in pixels.increment() }
    defer {
      sampleSubscription.cancel()
      pixelSubscription.cancel()
    }

    output.emit(sampleBuffer: empty)

    XCTAssertEqual(samples.count, 1)
    XCTAssertEqual(pixels.count, 0)
  }

  /// The delivery lock is not recursive and must never block: a handler that emits back into
  /// the output it is being called from gets that frame dropped, not delivered on top of the
  /// first and not deadlocked. A blocking lock here would hang the camera's delegate queue.
  func testAHandlerEmittingBackIntoItsOwnOutputIsDroppedNotNestedOrDeadlocked() throws {
    let output = VideoDataOutput()
    let sample = try CMSampleBuffer.wrapping(imageBuffer: try makePixelBuffer(luma: 5), presentationTime: .zero)
    let deliveries = FrameCounter()
    let subscription = output.sampleBufferBus.addHandler { frame in
      deliveries.increment()
      output.emit(sampleBuffer: frame)
    }
    defer { subscription.cancel() }

    assertFinishes {
      output.emit(sampleBuffer: sample)
    }

    XCTAssertEqual(deliveries.count, 1, "the re-entrant frame should have been dropped")
  }

  /// `CoreImageFilter` applies its filters in place and so relies on never being entered
  /// concurrently. Several producers emitting at once must be serialised by dropping, not by
  /// running handlers on top of one another.
  func testFramesAreNeverDeliveredConcurrently() throws {
    let output = VideoDataOutput()
    let sample = try CMSampleBuffer.wrapping(imageBuffer: try makePixelBuffer(luma: 9), presentationTime: .zero)
    let overlap = OverlapGauge()
    let delivered = FrameCounter()
    let subscription = output.pixelBufferBus.addHandler { _ in
      overlap.enter()
      // Long enough that concurrent producers would certainly collide without the lock.
      Thread.sleep(forTimeInterval: 0.0005)
      overlap.leave()
      delivered.increment()
    }
    defer { subscription.cancel() }

    let group = DispatchGroup()
    let producers = DispatchQueue(label: "CapturerTests.producers", attributes: .concurrent)
    let producerCount = 4
    let emitsPerProducer = 200
    for _ in 0..<producerCount {
      producers.async(group: group) {
        for _ in 0..<emitsPerProducer {
          output.emit(sampleBuffer: sample)
        }
      }
    }
    XCTAssertEqual(group.wait(timeout: .now() + 20), .success, "the producers did not finish")

    XCTAssertEqual(overlap.peakInFlight, 1, "a handler was entered while another delivery was in progress")
    XCTAssertGreaterThanOrEqual(delivered.count, 1)
    XCTAssertLessThanOrEqual(delivered.count, producerCount * emitsPerProducer)
  }

  // MARK: - CMSampleBuffer.wrapping

  func testWrappedFrameCarriesTheImageAndTimingACaptureOutputWould() throws {
    let pixelBuffer = try makePixelBuffer(luma: 10)
    let time = CMTime(value: 7, timescale: 30)
    let sample = try CMSampleBuffer.wrapping(imageBuffer: pixelBuffer, presentationTime: time)

    XCTAssertTrue(sample.imageBuffer === pixelBuffer)
    XCTAssertEqual(sample.presentationTimeStamp, time)
    XCTAssertFalse(sample.duration.isValid, "AVCaptureVideoDataOutput frames carry no duration")
    XCTAssertFalse(sample.decodeTimeStamp.isValid)
    XCTAssertTrue(CMSampleBufferDataIsReady(sample))
    let description = try XCTUnwrap(sample.formatDescription)
    XCTAssertEqual(description.dimensions.width, Int32(frameSize.width))
    XCTAssertEqual(description.dimensions.height, Int32(frameSize.height))
    XCTAssertEqual(description.mediaSubType.rawValue, kCVPixelFormatType_32BGRA)
  }

  // MARK: - LatestValueSlot

  func testSlotSignalsOnlyTheFirstOfABurstAndHandsOutTheNewest() {
    let slot = LatestValueSlot<Int>()
    XCTAssertNil(slot.take())
    XCTAssertTrue(slot.replace(with: 1))
    XCTAssertFalse(slot.replace(with: 2))
    XCTAssertFalse(slot.replace(with: 3))
    XCTAssertEqual(slot.take(), 3)
    XCTAssertNil(slot.take())
    XCTAssertTrue(slot.replace(with: 4), "empty again, so the next producer must schedule a consumer")
  }

  /// The contract `PixelBufferView` relies on: one consumer per `true`, every consumer finds a
  /// value, nothing is left behind, and a serial producer's consumer never sees an older frame.
  func testEverySignalledConsumerFindsAValueAndValuesOnlyMoveForward() {
    let slot = LatestValueSlot<Int>()
    let consumer = DispatchQueue(label: "CapturerTests.consumer")
    let taken = SynchronizedList<Int?>()
    let signals = FrameCounter()
    let total = 10_000

    for value in 1...total {
      guard slot.replace(with: value) else { continue }
      signals.increment()
      consumer.async { taken.append(slot.take()) }
    }
    consumer.sync {}

    let values = taken.snapshot
    XCTAssertEqual(values.count, signals.count)
    XCTAssertFalse(values.contains(nil), "a consumer was scheduled for an empty slot")
    XCTAssertNil(slot.take(), "a value was left behind with no consumer scheduled for it")
    XCTAssertEqual(values.last ?? nil, total, "the consumer's last frame must be the newest")
    let shown = values.compactMap { $0 }
    XCTAssertEqual(shown, shown.sorted(), "an older frame was shown after a newer one")
  }

  func testSlotInvariantsHoldUnderConcurrentProducers() {
    let slot = LatestValueSlot<Int>()
    let consumer = DispatchQueue(label: "CapturerTests.consumer")
    let producers = DispatchQueue(label: "CapturerTests.producers", attributes: .concurrent)
    let group = DispatchGroup()
    let taken = SynchronizedList<Int?>()
    let signals = FrameCounter()

    for value in 1...10_000 {
      producers.async(group: group) {
        guard slot.replace(with: value) else { return }
        signals.increment()
        consumer.async { taken.append(slot.take()) }
      }
    }
    XCTAssertEqual(group.wait(timeout: .now() + 20), .success, "the producers did not finish")
    consumer.sync {}

    XCTAssertEqual(taken.snapshot.count, signals.count)
    XCTAssertFalse(taken.snapshot.contains(nil), "a consumer was scheduled for an empty slot")
    XCTAssertNil(slot.take(), "a value was left behind with no consumer scheduled for it")
  }

  // MARK: - Preview view

  /// Frames arrive off-main and the layer is set on main; of a burst, the newest frame is the
  /// one that ends up on screen.
  @MainActor
  func testPreviewViewShowsTheNewestFrameOnMain() async throws {
    let output = VideoDataOutput()
    let view = PixelBufferView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
    view.attach(output: output)
    let first = try CMSampleBuffer.wrapping(imageBuffer: try makePixelBuffer(luma: 1), presentationTime: .zero)
    let newestPixelBuffer = try makePixelBuffer(luma: 2)
    let newest = try CMSampleBuffer.wrapping(
      imageBuffer: newestPixelBuffer,
      presentationTime: CMTime(value: 1, timescale: 30)
    )

    await Task.detached {
      output.emit(sampleBuffer: first)
      output.emit(sampleBuffer: newest)
    }.value

    // Polled on main so the hop the view scheduled onto the main queue gets to run.
    let deadline = Date().addingTimeInterval(5)
    while (view.layer.contents as AnyObject?) !== newestPixelBuffer, Date() < deadline {
      try await Task.sleep(nanoseconds: 50_000_000)
    }
    XCTAssertTrue(
      (view.layer.contents as AnyObject?) === newestPixelBuffer,
      "the layer should show the newest frame, not an older one and not nothing"
    )
  }

  /// Re-attaching while a frame from the previous output is still queued for main must not
  /// paint that frame. Emitting on main here keeps the hop queued behind the test until it
  /// yields, so the re-attach is guaranteed to happen first.
  @MainActor
  func testReattachingDiscardsAFrameStillOnItsWayFromThePreviousOutput() async throws {
    let previousOutput = VideoDataOutput()
    let nextOutput = VideoDataOutput()
    let view = PixelBufferView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
    let staleFrame = try CMSampleBuffer.wrapping(imageBuffer: try makePixelBuffer(luma: 1), presentationTime: .zero)
    let livePixelBuffer = try makePixelBuffer(luma: 2)
    let liveFrame = try CMSampleBuffer.wrapping(imageBuffer: livePixelBuffer, presentationTime: .zero)

    view.attach(output: previousOutput)
    previousOutput.emit(sampleBuffer: staleFrame)
    view.attach(output: nextOutput)

    try await Task.sleep(nanoseconds: 100_000_000)
    XCTAssertNil(view.layer.contents, "a frame from the replaced subscription was painted")

    nextOutput.emit(sampleBuffer: liveFrame)
    try await Task.sleep(nanoseconds: 100_000_000)
    XCTAssertTrue((view.layer.contents as AnyObject?) === livePixelBuffer, "the new output's frame should be painted")
  }

  // MARK: - Test support

  private actor Received {
    var count = 0
    func increment() { count += 1 }
  }

  private final class FrameCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return _count }
    func increment() { lock.lock(); _count += 1; lock.unlock() }
  }

  /// An append-only record that handlers on the delivery thread can write to.
  private final class SynchronizedList<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Value] = []
    func append(_ value: Value) { lock.lock(); values.append(value); lock.unlock() }
    var snapshot: [Value] { lock.lock(); defer { lock.unlock() }; return values }
  }

  private final class SynchronizedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value?
    var value: Value? {
      get { lock.lock(); defer { lock.unlock() }; return _value }
      set { lock.lock(); _value = newValue; lock.unlock() }
    }
  }

  /// Tracks how many handlers are inside a delivery at once, and the most there ever were.
  private final class OverlapGauge: @unchecked Sendable {
    private let lock = NSLock()
    private var inFlight = 0
    private var peak = 0
    func enter() { lock.lock(); inFlight += 1; peak = max(peak, inFlight); lock.unlock() }
    func leave() { lock.lock(); inFlight -= 1; lock.unlock() }
    var peakInFlight: Int { lock.lock(); defer { lock.unlock() }; return peak }
  }

  private static func currentThreadID() -> mach_port_t {
    pthread_mach_thread_np(pthread_self())
  }

  /// Runs `body` off the test thread and fails, instead of hanging the suite, if it does not
  /// finish — the way a lock held through a handler loop would fail.
  private func assertFinishes(
    within seconds: TimeInterval = 2,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ body: @escaping @Sendable () -> Void
  ) {
    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
      body()
      done.signal()
    }
    XCTAssertEqual(done.wait(timeout: .now() + seconds), .success, "deadlocked", file: file, line: line)
  }

  private struct WaitTimedOut: Error {
    let waitingFor: String
  }

  /// Polls until `condition` holds. Fails the test *and* throws on timeout, so the assertions
  /// that follow do not fail a second time with a misleading message.
  ///
  /// The default allows for `AVQueuePlayer`'s cold start on a loaded simulator; it costs nothing
  /// when the condition holds sooner.
  private func waitUntil(
    _ description: String,
    timeout: TimeInterval = 15,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: @escaping () async -> Bool
  ) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if await condition() { return }
      try await Task.sleep(nanoseconds: 50_000_000)
    }
    XCTFail("timed out waiting for: \(description)", file: file, line: line)
    throw WaitTimedOut(waitingFor: description)
  }
}
