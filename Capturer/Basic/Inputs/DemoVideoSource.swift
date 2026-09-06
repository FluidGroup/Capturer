@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
import Foundation
import QuartzCore

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
///
/// Playback is `AVPlayer`'s: it keeps the clock, decodes in hardware where there is any, and
/// loops the videos through a queue. A display link on its own thread asks the player's video
/// output, once per display refresh, for the frame that belongs to that instant, and publishes
/// it — so what goes out is always the frame for *now*, never a backlog of frames for then. A
/// consumer that cannot keep up costs frames, the same as it would with a camera, and nothing
/// else.
public final class DemoVideoSource: @unchecked Sendable {

  public enum Error: Swift.Error {
    /// A video was named that is not present. Deliberately fatal to the caller rather than
    /// silently falling back: a run that quietly showed the wrong footage, or none, would be
    /// worse than one that stopped.
    case videoNotFound(URL)
    case noVideosAvailable
    case couldNotReadVideo(URL)
  }

  /// A video read once, ready to be played any number of times.
  private struct PreparedVideo {
    let asset: AVURLAsset
    /// Applies the track's `preferredTransform` to the frames themselves.
    ///
    /// A camera records in the sensor's own landscape orientation and it is the preview layer
    /// that turns the picture upright — and that layer is not in this path. Frames straight off
    /// the track are sideways for every consumer: the preview, and the shutter, which returns the
    /// buffer rather than anything the preview did to it. Rotating here is the one place that
    /// fixes both, and it is the same rotation the file already carries.
    let composition: AVVideoComposition
    let renderSize: CGSize
    let nominalFrameRate: Float
  }

  /// One video in the player's queue, and the output its frames are read from.
  private struct QueuedVideo {
    let item: AVPlayerItem
    let output: AVPlayerItemVideoOutput
    let renderSize: CGSize
  }

  private let videos: [PreparedVideo]
  private let pixelFormat: OSType

  private let lock = NSLock()
  private var isRunning = false
  private var player: AVQueuePlayer?
  /// In playback order: the video playing, then the one after it.
  private var queued: [QueuedVideo] = []
  private var nextVideoIndex = 0
  private var endObserver: (any NSObjectProtocol)?
  private var frameThread: FrameThread?
  private var _latestPixelBuffer: CVPixelBuffer?
  private var _naturalSize: CGSize

  /// The frame most recently published.
  ///
  /// This is what a capture returns while the demo source is driving: the shutter takes whatever
  /// is on screen, exactly as it does with a camera.
  public var latestPixelBuffer: CVPixelBuffer? {
    lock.lock()
    defer { lock.unlock() }
    return _latestPixelBuffer
  }

  /// The size of the frames being published — the video's, once its rotation has been applied —
  /// for callers that need to report an aspect ratio the way `PreviewOutput` reports the camera's.
  public var naturalSize: CGSize {
    lock.lock()
    defer { lock.unlock() }
    return _naturalSize
  }

  private init(videos: [PreparedVideo], pixelFormat: OSType) {
    self.videos = videos
    self.pixelFormat = pixelFormat
    self._naturalSize = videos[0].renderSize
  }

  deinit {
    stop()
  }

  /// Reads the videos and returns a source ready to play them.
  ///
  /// - Parameters:
  ///   - videoURLs: Played in order, looping back to the first after the last. Passing a single
  ///     URL loops that one.
  ///   - pixelFormat: Defaults to `kCVPixelFormatType_32BGRA`, matching a default
  ///     `AVCaptureVideoDataOutput`.
  public static func prepare(
    videoURLs: [URL],
    pixelFormat: OSType = kCVPixelFormatType_32BGRA
  ) async throws -> DemoVideoSource {
    guard !videoURLs.isEmpty else {
      throw Error.noVideosAvailable
    }

    var videos: [PreparedVideo] = []
    for url in videoURLs {
      guard FileManager.default.fileExists(atPath: url.path) else {
        throw Error.videoNotFound(url)
      }
      let asset = AVURLAsset(url: url)
      // A recording has one video track; a file with several would be something other than a
      // recording, and the first is still the one a player would show.
      guard let track = try await asset.loadTracks(withMediaType: .video).first else {
        throw Error.couldNotReadVideo(url)
      }
      let nominalFrameRate = try await track.load(.nominalFrameRate)
      let composition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: asset)
      videos.append(PreparedVideo(
        asset: asset,
        composition: composition,
        renderSize: composition.renderSize,
        nominalFrameRate: nominalFrameRate
      ))
    }
    return DemoVideoSource(videos: videos, pixelFormat: pixelFormat)
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

  /// Starts publishing frames into `output`, on the display's cadence, from a thread of its own.
  public func start(feeding output: VideoDataOutput) {
    lock.lock()
    guard !isRunning else {
      lock.unlock()
      return
    }
    isRunning = true

    let player = AVQueuePlayer()
    // Local files: there is nothing to buffer for, and waiting would only delay the first frame.
    player.automaticallyWaitsToMinimizeStalling = false
    player.actionAtItemEnd = .advance
    self.player = player

    // Two videos queued at all times — the one playing and the one after it — so the hand-over
    // is seamless and a single video simply follows itself.
    enqueueNextVideo(into: player)
    enqueueNextVideo(into: player)

    endObserver = NotificationCenter.default.addObserver(
      forName: AVPlayerItem.didPlayToEndTimeNotification,
      object: nil,
      queue: nil
    ) { [weak self] notification in
      guard let item = notification.object as? AVPlayerItem else { return }
      self?.videoDidEnd(item)
    }

    // The highest rate among the videos, so a 60 fps recording is shown at 60 even when queued
    // behind a 30 fps one; a video with fewer frames than refreshes simply has no new frame to
    // give on some ticks.
    let preferredFrameRate = videos.map(\.nominalFrameRate).max() ?? 30
    let thread = FrameThread(preferredFrameRate: preferredFrameRate) { [weak self] hostTime in
      self?.publishFrame(at: hostTime, into: output)
    }
    frameThread = thread
    lock.unlock()

    thread.start()
    player.play()
  }

  public func stop() {
    lock.lock()
    isRunning = false
    let thread = frameThread
    frameThread = nil
    let player = self.player
    self.player = nil
    queued.removeAll()
    if let endObserver {
      NotificationCenter.default.removeObserver(endObserver)
    }
    endObserver = nil
    lock.unlock()

    thread?.stop()
    player?.pause()
    player?.removeAllItems()
  }

  /// Appends the next video to the player. Called with the lock held.
  private func enqueueNextVideo(into player: AVQueuePlayer) {
    let video = videos[nextVideoIndex % videos.count]
    nextVideoIndex += 1

    // A fresh item each time: a player item plays once, so looping means a new item for the same
    // asset, which is what the prepared asset is kept for.
    let item = AVPlayerItem(asset: video.asset)
    item.videoComposition = video.composition
    let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
      kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
      // Without this the buffers are not IOSurface-backed, and `CALayer.contents` — how a preview
      // draws a frame — silently displays nothing at all. The camera's buffers are always
      // IOSurface-backed, so this is part of handing downstream the same thing a camera would.
      kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary
    ])
    item.add(output)

    queued.append(QueuedVideo(item: item, output: output, renderSize: video.renderSize))
    player.insert(item, after: nil)
  }

  private func videoDidEnd(_ item: AVPlayerItem) {
    lock.lock()
    defer { lock.unlock() }
    guard isRunning, let player, let index = queued.firstIndex(where: { $0.item === item }) else {
      return
    }
    queued.remove(at: index)
    enqueueNextVideo(into: player)
  }

  /// Publishes the frame that belongs to `hostTime`, if there is a new one. On the frame thread.
  private func publishFrame(at hostTime: CFTimeInterval, into output: VideoDataOutput) {
    lock.lock()
    let running = isRunning
    let candidates = queued
    lock.unlock()
    guard running else { return }

    // The video playing is first in the queue; the one after it is asked too, because the player
    // moves on to it a moment before the end of the first is reported.
    for video in candidates {
      let itemTime = video.output.itemTime(forHostTime: hostTime)
      guard video.output.hasNewPixelBuffer(forItemTime: itemTime),
            let pixelBuffer = video.output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil)
      else {
        continue
      }

      lock.lock()
      _latestPixelBuffer = pixelBuffer
      _naturalSize = video.renderSize
      lock.unlock()

      do {
        let sampleBuffer = try CMSampleBuffer.wrapping(imageBuffer: pixelBuffer, presentationTime: itemTime)
        output.emit(sampleBuffer: sampleBuffer)
      } catch {
        Log.error(.capture, "DemoVideoSource could not wrap a frame as a sample buffer: \(error)")
      }
      return
    }
  }

  /// A thread whose only job is to run a display link.
  ///
  /// Frames are wanted on the display's cadence, and a display link is the one clock that has
  /// it — but it needs a run loop, and the main run loop is the wrong one: publishing from there
  /// would put every frame's handlers on the main thread. So the link lives on a run loop of its
  /// own, and the main thread never sees a frame it did not ask for.
  private final class FrameThread: Thread, @unchecked Sendable {
    private let preferredFrameRate: Float
    private let tick: @Sendable (CFTimeInterval) -> Void
    private let lock = NSLock()
    private var runLoop: CFRunLoop?

    init(preferredFrameRate: Float, tick: @escaping @Sendable (CFTimeInterval) -> Void) {
      self.preferredFrameRate = preferredFrameRate
      self.tick = tick
      super.init()
      name = "Capturer.DemoVideoSource.frames"
      qualityOfService = .userInteractive
    }

    override func main() {
      lock.lock()
      runLoop = CFRunLoopGetCurrent()
      lock.unlock()

      let link = CADisplayLink(target: self, selector: #selector(displayLinkDidFire(_:)))
      link.preferredFrameRateRange = CAFrameRateRange(
        minimum: 30,
        maximum: 120,
        preferred: max(30, preferredFrameRate)
      )
      link.add(to: .current, forMode: .default)

      while !isCancelled {
        RunLoop.current.run(mode: .default, before: .distantFuture)
      }

      link.invalidate()
    }

    func stop() {
      cancel()
      lock.lock()
      let runLoop = self.runLoop
      lock.unlock()
      if let runLoop {
        CFRunLoopStop(runLoop)
      }
    }

    @objc private func displayLinkDidFire(_ link: CADisplayLink) {
      guard !isCancelled else { return }
      tick(link.targetTimestamp)
    }
  }
}
