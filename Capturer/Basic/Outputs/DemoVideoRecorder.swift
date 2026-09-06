@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
import Foundation

/// Records the camera's frames to a file, for later playback by `DemoVideoSource`.
///
/// Deliberately records the *frames*, not the screen. It is fed from the same pixel buffers the
/// preview draws, so overlays, controls and anything else the app puts on top are absent by
/// construction rather than by cropping — which is what makes the result usable as a camera
/// substitute instead of a screen recording.
public final class DemoVideoRecorder: @unchecked Sendable {

  public enum Error: Swift.Error {
    case alreadyRecording
    case couldNotCreateWriter(URL)
    case writeFailed(Swift.Error)
    case nothingRecorded
  }

  private let lock = NSLock()
  private var writer: AVAssetWriter?
  private var input: AVAssetWriterInput?
  private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
  private var startTime: CMTime?
  private var isRecording = false
  private var frameCount = 0

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
  ///   - size: The frame size to record. Must match the buffers subsequently appended.
  ///   - rotationDegrees: How far the frames must be turned to be upright, which is what a camera
  ///     connection's `videoRotationAngle` reports. Recorded onto the track rather than applied to
  ///     the buffers: rotating each frame on the way in would cost a rotation per frame during a
  ///     live capture and risk dropping them, and the file would stop saying what the camera
  ///     actually produced. `DemoVideoSource` applies it on the way out, where the cost does not
  ///     matter and one place serves the preview and the shutter alike. Zero records no rotation.
  ///   - frameRate: The rate the frames will arrive at. Sizes the bit rate — the same footage at
  ///     twice the frame rate needs twice the bits to look the same — and tells the encoder what
  ///     to expect.
  public func start(
    to url: URL,
    size: CGSize,
    rotationDegrees: CGFloat = 0,
    frameRate: Double = 30
  ) throws {
    lock.lock()
    defer { lock.unlock() }

    guard !isRecording else { throw Error.alreadyRecording }

    try? FileManager.default.removeItem(at: url)

    guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else {
      throw Error.couldNotCreateWriter(url)
    }

    let settings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: Int(size.width),
      AVVideoHeightKey: Int(size.height),
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: Self.bitRate(for: size, framesPerSecond: frameRate),
        AVVideoExpectedSourceFrameRateKey: Int(frameRate.rounded())
      ]
    ]
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = true
    if rotationDegrees != 0 {
      input.transform = CGAffineTransform(rotationAngle: rotationDegrees * .pi / 180)
    }

    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: Int(size.width),
        kCVPixelBufferHeightKey as String: Int(size.height)
      ]
    )

    guard writer.canAdd(input) else { throw Error.couldNotCreateWriter(url) }
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    self.writer = writer
    self.input = input
    self.adaptor = adaptor
    self.outputURL = url
    self.startTime = nil
    self.frameCount = 0
    self.isRecording = true
  }

  /// Appends one frame. Safe to call from the pixel buffer bus's queue; frames arriving while the
  /// writer is not ready are dropped rather than queued, exactly as a real capture would drop.
  public func append(_ pixelBuffer: CVPixelBuffer, at time: CMTime) {
    lock.lock()
    defer { lock.unlock() }

    guard isRecording, let adaptor, let input, input.isReadyForMoreMediaData else { return }

    let presentationTime: CMTime
    if let startTime {
      presentationTime = CMTimeSubtract(time, startTime)
    } else {
      startTime = time
      presentationTime = .zero
    }

    if adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
      frameCount += 1
    }
  }

  /// Finishes the file and hands back where it was written.
  public func finish() async throws -> URL {
    let (writer, input, outputURL) = try claimForFinishing()

    input.markAsFinished()
    await writer.finishWriting()

    if let error = writer.error {
      clearWriterState()
      throw Error.writeFailed(error)
    }

    clearWriterState()
    return outputURL
  }

  /// Takes the writer out of the recorder under the lock, so the `await` above happens without
  /// holding it — Swift 6 forbids `NSLock` across a suspension, and holding a lock across the
  /// writer finishing would be wrong regardless.
  private func claimForFinishing() throws -> (AVAssetWriter, AVAssetWriterInput, URL) {
    try lock.withLock {
      guard isRecording, let writer, let input, let outputURL else {
        throw Error.nothingRecorded
      }
      isRecording = false
      guard frameCount > 0 else {
        writer.cancelWriting()
        throw Error.nothingRecorded
      }
      return (writer, input, outputURL)
    }
  }

  private func clearWriterState() {
    lock.withLock {
      writer = nil
      input = nil
      adaptor = nil
    }
  }
}
