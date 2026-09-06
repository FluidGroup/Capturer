@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
import Foundation

/// Records the camera's frames to a file, for later playback by `DemoVideoSource`.
///
/// Deliberately records the *frames*, not the screen. It is fed from the same sample buffers the
/// preview draws, so overlays, controls and anything else the app puts on top are absent by
/// construction rather than by cropping — which is what makes the result usable as a camera
/// substitute instead of a screen recording.
public final class DemoVideoRecorder: @unchecked Sendable {

  public enum Error: Swift.Error {
    case alreadyRecording
    /// Not finite and positive. The rate sizes the bit rate, and a non-positive bit rate is an
    /// Objective-C exception inside `AVAssetWriterInput`, not a thrown error.
    case invalidFrameRate(Double)
    /// Under a pixel in either dimension, or so small that the bit rate rounds to nothing.
    case invalidSize(CGSize)
    case couldNotCreateWriter(URL, underlying: Swift.Error)
    case couldNotAddInput(URL)
    /// The writer refused to start. `underlying` is whatever it reported, if anything.
    case couldNotStartWriting(URL, underlying: Swift.Error?)
    /// The writer stopped accepting frames without reporting an error of its own.
    case writerRefusedFrame
    case writeFailed(Swift.Error)
    /// Nothing reached the file. The counts say where the frames went, if any arrived at all.
    case nothingRecorded(DroppedFrames)
  }

  /// Frames handed to `append` that are not in the file, by reason.
  ///
  /// Counted rather than reported per frame: a 60 fps source can produce thousands, and the
  /// caller's use for them is a summary at the end.
  public struct DroppedFrames: Equatable, Sendable {
    /// The writer was still busy with earlier frames — the drop a real capture makes too.
    public var writerBusy = 0
    /// Presentation time non-numeric or not later than the previous frame's. The writer accepts
    /// such a frame and then fails the *entire file* at `finish`, so it is refused here instead.
    public var unusableTime = 0
    /// Not the dimensions recording started with; the writer would silently scale and crop.
    public var sizeMismatch = 0
    /// A sample buffer with no image buffer.
    public var withoutImage = 0
    /// Arrived after the writer had failed. That failure is what `finish` throws.
    public var afterFailure = 0

    public var total: Int { writerBusy + unusableTime + sizeMismatch + withoutImage + afterFailure }
  }

  /// A finished file and what went into it.
  public struct Recording: Sendable {
    public let url: URL
    public let frameCount: Int
    public let droppedFrames: DroppedFrames
  }

  /// What `finish` takes out of the recorder before it awaits the writer.
  private struct Claimed {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    let url: URL
    let frameCount: Int
    let droppedFrames: DroppedFrames
  }

  private let lock = NSLock()
  private var writer: AVAssetWriter?
  private var input: AVAssetWriterInput?
  private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
  private var frameWidth = 0
  private var frameHeight = 0
  private var startTime: CMTime?
  private var lastPresentationTime: CMTime?
  private var isRecording = false
  private var frameCount = 0
  private var droppedFrames = DroppedFrames()
  private var failure: Swift.Error?

  public private(set) var outputURL: URL?

  public init() {}

  /// What to spend on a second of video at `size`.
  ///
  /// Set explicitly because the alternative is whatever AVFoundation picks, which for a full-size
  /// camera frame is around 15 Mbps — a minute of that is over a hundred megabytes, for footage
  /// whose entire purpose is to be committed alongside an app as a development aid. Scaled by
  /// pixel count rather than fixed, so it stays sane whatever the camera hands over.
  private static func bitRate(for size: CGSize, framesPerSecond: Double) -> Int {
    // Comfortably above where H.264 shows artefacts on camera footage, and roughly a fifth of the
    // default. Chosen against real recordings rather than derived.
    let bitsPerPixel = 0.05
    return Int(size.width * size.height * framesPerSecond * bitsPerPixel)
  }

  /// Begins recording to `url`, overwriting anything already there.
  ///
  /// - Parameters:
  ///   - size: The frame size to record. Buffers of any other size are dropped and counted
  ///     rather than written, because the writer would otherwise scale and crop them silently.
  ///   - rotationDegrees: How far the frames must be turned to be upright, which is what a camera
  ///     connection's `videoRotationAngle` reports. Recorded onto the track rather than applied to
  ///     the buffers: rotating each frame on the way in would cost a rotation per frame during a
  ///     live capture and risk dropping them, and the file would stop saying what the camera
  ///     actually produced. `DemoVideoSource` applies it on the way out, where the cost does not
  ///     matter and one place serves the preview and the shutter alike. Zero records no rotation.
  ///   - frameRate: The rate the frames will arrive at. Sizes the bit rate — the same footage at
  ///     twice the frame rate needs twice the bits to look the same — and tells the encoder which
  ///     level to pick. No default: an encoder told 30 and fed 60 may drop frames to stay within
  ///     the level it chose, drops that happen inside the encoder and never show in the counts
  ///     here.
  public func start(
    to url: URL,
    size: CGSize,
    rotationDegrees: CGFloat = 0,
    frameRate: Double
  ) throws {
    lock.lock()
    defer { lock.unlock() }

    guard !isRecording else { throw Error.alreadyRecording }
    // A non-positive bit rate is an Objective-C exception in AVAssetWriterInput, not an error,
    // and either a bad rate or a tiny size produces one.
    guard frameRate.isFinite, frameRate > 0 else { throw Error.invalidFrameRate(frameRate) }
    let bitRate = Self.bitRate(for: size, framesPerSecond: frameRate)
    guard size.width >= 1, size.height >= 1, bitRate > 0 else { throw Error.invalidSize(size) }

    try? FileManager.default.removeItem(at: url)

    let writer: AVAssetWriter
    do {
      writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    } catch {
      throw Error.couldNotCreateWriter(url, underlying: error)
    }

    let settings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: Int(size.width),
      AVVideoHeightKey: Int(size.height),
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: bitRate,
        AVVideoExpectedSourceFrameRateKey: Int(frameRate.rounded())
      ]
    ]
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = true
    if rotationDegrees != 0 {
      input.transform = CGAffineTransform(rotationAngle: rotationDegrees * .pi / 180)
    }

    // No pool: the frames arrive already allocated by the camera. Attributes here would only
    // describe a pool nobody draws from, and validate nothing about what is appended.
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: nil
    )

    guard writer.canAdd(input) else { throw Error.couldNotAddInput(url) }
    writer.add(input)
    // A writer that cannot start says so only here: afterwards the input still claims to be
    // ready, every append returns false, and `finish` would report "nothing recorded".
    guard writer.startWriting() else {
      throw Error.couldNotStartWriting(url, underlying: writer.error)
    }
    writer.startSession(atSourceTime: .zero)

    self.writer = writer
    self.input = input
    self.adaptor = adaptor
    self.outputURL = url
    self.frameWidth = Int(size.width)
    self.frameHeight = Int(size.height)
    self.startTime = nil
    self.lastPresentationTime = nil
    self.frameCount = 0
    self.droppedFrames = DroppedFrames()
    self.failure = nil
    self.isRecording = true
  }

  /// Appends one frame from a capture bus, timed by its own presentation stamp.
  ///
  /// The stamp comes from the capture clock, which only moves forward. A caller stamping frames
  /// with the wall clock instead would hand the writer a step backwards on the next clock
  /// correction, and one such frame fails the whole file at `finish`.
  public func append(_ sampleBuffer: CMSampleBuffer) {
    guard let pixelBuffer = sampleBuffer.takeCVPixelBuffer() else {
      lock.withLock { droppedFrames.withoutImage += 1 }
      return
    }
    append(pixelBuffer, at: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
  }

  /// Appends one frame. Safe to call from a bus's delivery queue; frames arriving while the
  /// writer is not ready are dropped rather than queued, exactly as a real capture would drop.
  /// Every drop is counted and reported by `finish`.
  public func append(_ pixelBuffer: CVPixelBuffer, at time: CMTime) {
    lock.lock()
    defer { lock.unlock() }

    guard isRecording, let writer, let adaptor, let input else { return }
    guard failure == nil else {
      droppedFrames.afterFailure += 1
      return
    }
    guard CVPixelBufferGetWidth(pixelBuffer) == frameWidth,
          CVPixelBufferGetHeight(pixelBuffer) == frameHeight
    else {
      droppedFrames.sizeMismatch += 1
      return
    }
    // A non-numeric time is an Objective-C exception in `append`, not a false return.
    guard time.isNumeric else {
      droppedFrames.unusableTime += 1
      return
    }
    guard input.isReadyForMoreMediaData else {
      droppedFrames.writerBusy += 1
      return
    }

    let presentationTime: CMTime
    if let startTime {
      presentationTime = CMTimeSubtract(time, startTime)
    } else {
      startTime = time
      presentationTime = .zero
    }
    // The writer accepts a repeated or earlier time and fails the entire file at `finish`.
    if let lastPresentationTime, presentationTime <= lastPresentationTime {
      droppedFrames.unusableTime += 1
      return
    }

    if adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
      frameCount += 1
      lastPresentationTime = presentationTime
    } else {
      // False only once the writer has failed — cancelled and completed are ruled out by
      // `isRecording` — and it stays failed. Going to the background does this on iOS.
      failure = writer.error ?? Error.writerRefusedFrame
      droppedFrames.afterFailure += 1
    }
  }

  /// Finishes the file and hands back where it was written, with what went into it.
  public func finish() async throws -> Recording {
    let claimed = try claimForFinishing()

    claimed.input.markAsFinished()
    await claimed.writer.finishWriting()

    if let error = claimed.writer.error {
      // A failed writer leaves its partial file behind. Named `demo_video_<n>.mov`, that is
      // exactly the file that must never be mistaken for a recording.
      try? FileManager.default.removeItem(at: claimed.url)
      throw Error.writeFailed(error)
    }
    return Recording(url: claimed.url, frameCount: claimed.frameCount, droppedFrames: claimed.droppedFrames)
  }

  /// Takes the writer *out* of the recorder under the lock, so the `await` above happens without
  /// holding it — Swift 6 forbids `NSLock` across a suspension, and holding a lock across the
  /// writer finishing would be wrong regardless. Taking it out, rather than leaving it in place
  /// to clear afterwards, also means a `start` that follows can never be undone by this
  /// finish's clean-up.
  private func claimForFinishing() throws -> Claimed {
    try lock.withLock {
      guard isRecording, let writer, let input, let outputURL else {
        throw Error.nothingRecorded(droppedFrames)
      }
      isRecording = false
      self.writer = nil
      self.input = nil
      self.adaptor = nil

      if let failure {
        // Cancelling a failed writer is a no-op, so its partial file has to be removed here.
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: outputURL)
        throw Error.writeFailed(failure)
      }
      guard frameCount > 0 else {
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: outputURL)
        throw Error.nothingRecorded(droppedFrames)
      }
      return Claimed(
        writer: writer,
        input: input,
        url: outputURL,
        frameCount: frameCount,
        droppedFrames: droppedFrames
      )
    }
  }
}
