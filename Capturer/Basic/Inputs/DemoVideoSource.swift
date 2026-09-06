@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
import Foundation

/// Plays recorded video into the capture pipeline in place of a camera.
///
/// Exists because the simulator has no camera, which makes the whole camera half of an app
/// untestable there — no preview, no capture, no screenshots or recordings of either. Rather than
/// build a second path for that case, this publishes frames onto the very buses
/// `VideoDataOutput` publishes camera frames onto, so the preview, filters, views and photo
/// capture all behave as they already do and none of them can tell the difference.
///
/// The frames are decoded to `pixelFormat`, which defaults to what an `AVCaptureVideoDataOutput`
/// vends. That is the detail that makes the substitution honest: the on-disk codec is irrelevant,
/// but the buffers handed downstream must be the same shape the camera would have handed over,
/// or subtle differences appear in filters and rendering.
public final class DemoVideoSource: @unchecked Sendable {

  public enum Error: Swift.Error {
    /// A video was named that is not present. Deliberately fatal to the caller rather than
    /// silently falling back: a run that quietly showed the wrong footage, or none, would be
    /// worse than one that stopped.
    case videoNotFound(URL)
    case noVideosAvailable
    case couldNotReadVideo(URL)
  }

  /// Videos to play, in order.
  private let videoURLs: [URL]
  private let pixelFormat: OSType
  private let queue = DispatchQueue(label: "Capturer.DemoVideoSource")

  private let lock = NSLock()
  private var currentIndex = 0
  private var reader: AVAssetReader?
  private var trackOutput: AVAssetReaderVideoCompositionOutput?
  private var isRunning = false
  private var timer: DispatchSourceTimer?
  private var _latestPixelBuffer: CVPixelBuffer?

  /// The frame most recently published.
  ///
  /// This is what a capture returns while the demo source is driving: the shutter takes whatever
  /// is on screen, exactly as it does with a camera.
  public var latestPixelBuffer: CVPixelBuffer? {
    lock.lock()
    defer { lock.unlock() }
    return _latestPixelBuffer
  }

  /// The natural size of the video being played, for callers that need to report an aspect ratio
  /// the way `PreviewOutput` reports the camera's.
  public private(set) var naturalSize: CGSize = .zero

  /// - Parameters:
  ///   - videoURLs: Played in order, looping back to the first after the last. Passing a single
  ///     URL loops that one.
  ///   - pixelFormat: Defaults to `kCVPixelFormatType_32BGRA`, matching a default
  ///     `AVCaptureVideoDataOutput`.
  public init(
    videoURLs: [URL],
    pixelFormat: OSType = kCVPixelFormatType_32BGRA
  ) throws {
    guard !videoURLs.isEmpty else {
      throw Error.noVideosAvailable
    }
    for url in videoURLs where !FileManager.default.fileExists(atPath: url.path) {
      throw Error.videoNotFound(url)
    }
    self.videoURLs = videoURLs
    self.pixelFormat = pixelFormat
  }

  /// Every `demo_video_<n>` in a bundle, in ascending order of `n`.
  ///
  /// Numbering starts at zero and stops at the first gap, so adding videos means adding files
  /// with no list to keep in step.
  public static func bundledVideoURLs(
    in bundle: Bundle = .main,
    prefix: String = "demo_video_",
    extensions: [String] = ["mov", "mp4"]
  ) -> [URL] {
    var urls: [URL] = []
    var index = 0
    while true {
      let found = extensions.lazy.compactMap {
        bundle.url(forResource: "\(prefix)\(index)", withExtension: $0)
      }.first
      guard let found else { break }
      urls.append(found)
      index += 1
    }
    return urls
  }

  /// Starts publishing frames into `output`.
  public func start(feeding output: VideoDataOutput) {
    lock.lock()
    guard !isRunning else {
      lock.unlock()
      return
    }
    isRunning = true
    lock.unlock()

    queue.async { [weak self] in
      self?.beginReading(startingAt: 0, output: output)
    }
  }

  public func stop() {
    lock.lock()
    isRunning = false
    timer?.cancel()
    timer = nil
    reader?.cancelReading()
    reader = nil
    trackOutput = nil
    lock.unlock()
  }

  private func beginReading(startingAt index: Int, output: VideoDataOutput) {
    let url = videoURLs[index % videoURLs.count]
    let asset = AVURLAsset(url: url)

    guard
      let track = asset.tracks(withMediaType: .video).first,
      let reader = try? AVAssetReader(asset: asset)
    else {
      Log.error(.capture, "DemoVideoSource could not read \(url.lastPathComponent)")
      return
    }

    let settings: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
      // Without this the decoded buffers are not IOSurface-backed, and `CALayer.contents` — how
      // the preview draws a frame — silently displays nothing at all. The camera's buffers are
      // always IOSurface-backed, so this is part of handing downstream the same thing a camera
      // would have.
      kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary
    ]

    // Read through a video composition rather than straight off the track, so the track's
    // `preferredTransform` is applied to the frames themselves.
    //
    // A camera records in the sensor's own landscape orientation and it is the preview layer that
    // turns the picture upright — and that layer is not in this path. Reading the track directly
    // handed every consumer sideways frames: the preview drew them sideways, and so did a capture,
    // because the shutter returns the buffer rather than anything the preview did to it. Rotating
    // here is the one place that fixes both, and it is the same rotation the file already carries.
    let composition = AVMutableVideoComposition(propertiesOf: asset)
    let trackOutput = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: settings)
    trackOutput.videoComposition = composition
    // Copies, because frames outlive the read: the most recent one is held for a capture to
    // return, and the preview holds one as layer contents. Reusing the reader's memory under
    // either of those shows torn or recycled frames.
    trackOutput.alwaysCopiesSampleData = true

    guard reader.canAdd(trackOutput) else {
      Log.error(.capture, "DemoVideoSource could not attach a track output for \(url.lastPathComponent)")
      return
    }
    reader.add(trackOutput)
    guard reader.startReading() else {
      Log.error(.capture, "DemoVideoSource could not start reading \(url.lastPathComponent)")
      return
    }

    let frameRate = track.nominalFrameRate > 0 ? track.nominalFrameRate : 30
    let interval = 1.0 / Double(frameRate)

    lock.lock()
    self.reader = reader
    self.trackOutput = trackOutput
    self.currentIndex = index
    // The composition's render size, not the track's natural size: once a quarter-turn has been
    // applied those differ, and every caller asking for this wants the size of the frames it is
    // actually being handed.
    self.naturalSize = composition.renderSize
    lock.unlock()

    // Paced rather than read-as-fast-as-possible, so the preview moves at the speed it was
    // recorded at and a capture lands on a frame a person could have chosen.
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now(), repeating: interval)
    timer.setEventHandler { [weak self] in
      guard let self else { return }
      self.readNextFrame(into: output, index: index)
    }

    lock.lock()
    self.timer?.cancel()
    self.timer = timer
    lock.unlock()

    timer.resume()
  }

  private func readNextFrame(into output: VideoDataOutput, index: Int) {
    lock.lock()
    let running = isRunning
    let currentOutput = trackOutput
    lock.unlock()

    guard running, let currentOutput else { return }

    guard let sampleBuffer = currentOutput.copyNextSampleBuffer() else {
      // End of this video: move to the next, wrapping at the end so playback never stops.
      lock.lock()
      timer?.cancel()
      timer = nil
      reader?.cancelReading()
      reader = nil
      trackOutput = nil
      lock.unlock()

      let next = (index + 1) % videoURLs.count
      queue.async { [weak self] in
        self?.beginReading(startingAt: next, output: output)
      }
      return
    }

    if let pixelBuffer = sampleBuffer.takeCVPixelBuffer() {
      lock.lock()
      _latestPixelBuffer = pixelBuffer
      lock.unlock()
    }

    output.emit(sampleBuffer: sampleBuffer)
  }
}
