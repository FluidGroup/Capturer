@preconcurrency import AVFoundation
import UIKit
import ImageIO

/**
 An output node for photo capturing.
 Use ``PreviewOutput`` for previewing in UI.
 */

public final class PhotoOutput: _StatefulObjectBase, OutputNodeType, @unchecked Sendable {

    public struct CapturePhoto: Sendable {

    /// The captured photo.
    ///
    /// Typed as `CapturedPhotoRepresentable` rather than `AVCapturePhoto` so a photo that did not
    /// come from a camera can stand in — see that protocol. `AVCapturePhoto` conforms, so
    /// existing callers reaching through this for `fileDataRepresentation()` are unaffected.
    public let photo: any CapturedPhotoRepresentable

    public init(photo: any CapturedPhotoRepresentable) {
      self.photo = photo
    }

    /// The orientation the photo should be displayed at.
    ///
    /// Falls back to `.up` rather than trapping when metadata carries no orientation. The forced
    /// unwraps this replaces were safe only because AVFoundation always sets the key; a
    /// conformance that forgot it would have crashed the app rather than shown a rotated image.
    public var orientation: CGImagePropertyOrientation {
      guard
        let orientationValue = photo.metadata[String(kCGImagePropertyOrientation)] as? NSNumber,
        let orientation = CGImagePropertyOrientation(rawValue: orientationValue.uint32Value)
      else {
        return .up
      }
      return orientation
    }

    /**
     Creates an image from captured data
     */
    public func makeImage(isMirrored: Bool) -> UIImage? {
      guard let cgImage = photo.cgImageRepresentation() else {
        return nil
      }
      return .init(
        cgImage: cgImage,
        scale: 1,
        orientation: isMirrored ? orientation.uiImageOrientation.mirrored : orientation.uiImageOrientation
      )
    }

  }

  private let _output = AVCapturePhotoOutput()
  public var avCapturePhotoOutput: AVCapturePhotoOutput { _output }

  /// When set, captures take the frame this is currently showing instead of asking the camera.
  ///
  /// Set it to run the camera half of an app somewhere there is no camera. The shutter behaves as
  /// it always does — it takes what is on screen — and hands back a `CapturePhoto` that callers
  /// cannot distinguish from a photographed one.
#if DEBUG
  private let demoSourceLock = NSLock()
  private var _demoSource: DemoVideoSource?
  public var demoSource: DemoVideoSource? {
    get {
      demoSourceLock.lock()
      defer { demoSourceLock.unlock() }
      return _demoSource
    }
    set {
      demoSourceLock.lock()
      _demoSource = newValue
      demoSourceLock.unlock()
    }
  }
#endif

  public init(quality: AVCapturePhotoOutput.QualityPrioritization = .balanced) {
    super.init()

    _output.isHighResolutionCaptureEnabled = true
    _output.maxPhotoQualityPrioritization = quality
  }

  public func capture(with settings: AVCapturePhotoSettings, completion: @escaping (Result<CapturePhoto, Error>) -> Void) {

    // A demo source stands in for the camera entirely, so the capture is the frame on screen.
    // Checked before touching `_output`, which has no connection to capture through when there is
    // no camera behind it.
#if DEBUG
    if let demoSource {
      guard let pixelBuffer = demoSource.latestPixelBuffer else {
        completion(.failure(CaptureError.noFrameAvailable))
        return
      }
      completion(.success(.init(photo: PixelBufferCapturedPhoto(pixelBuffer: pixelBuffer))))
      return
    }
#endif

    var completionWrapper: ((Result<CapturePhoto, Error>) -> Void)!

    let proxy = _AVCapturePhotoCaptureDelegateProxy { photo, error in
      if let error = error {
        completionWrapper(.failure(error))
        return
      }
      completionWrapper(.success(.init(photo: photo)))
    }

    completionWrapper = {
      completion($0)
      withExtendedLifetime(proxy, {})
    }

    _output.capturePhoto(with: settings, delegate: proxy)

  }

  public enum CaptureError: Swift.Error {
    /// The demo source has not produced a frame yet.
    case noFrameAvailable
  }

  public func capture(with settings: AVCapturePhotoSettings) async throws -> CapturePhoto {
    // Camera permission is meaningless when a demo source is supplying the frames, and asking for
    // it would fail on exactly the platforms this exists to support.
#if DEBUG
    let isDrivenByDemoSource = demoSource != nil
#else
    let isDrivenByDemoSource = false
#endif
    if !isDrivenByDemoSource {
      guard AVCaptureDevice.authorizationStatus(for: .video).isAuthorized else { throw AVAuthorizationStatus.Error.notAuthorized }
    }
    return try await withCheckedThrowingContinuation { continuation in
      capture(with: settings) { result in
        continuation.resume(with: result)
      }
    }
  }

  //  private final class _AVCaptureVideoDataOutputSampleBufferDelegateProxy: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
  //
  //    var handlers: Handlers = .init()
  //
  //    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
  //
  //    }
  //
  //    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
  //      handlers.didOutput(sampleBuffer)
  //    }
  //
  //  }

  public func setUp(sessionInConfiguring: AVCaptureSession) {
    sessionInConfiguring.addOutput(_output)
  }

  public func tearDown(sessionInConfiguring: AVCaptureSession) {
    sessionInConfiguring.removeOutput(_output)
  }

  private final class _AVCapturePhotoCaptureDelegateProxy: NSObject, AVCapturePhotoCaptureDelegate {

    var onDidFinishProcessingPhoto: (AVCapturePhoto, Error?) -> Void

    init(
      onDidFinishProcessingPhoto: @escaping (AVCapturePhoto, Error?) -> Void
    ) {
      self.onDidFinishProcessingPhoto = onDidFinishProcessingPhoto
    }

    func photoOutput(_ output: AVCapturePhotoOutput, willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings) {

    }

    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {

    }

    func photoOutput(_ output: AVCapturePhotoOutput, didCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {

    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
      onDidFinishProcessingPhoto(photo, error)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {

    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishRecordingLivePhotoMovieForEventualFileAt outputFileURL: URL, resolvedSettings: AVCaptureResolvedPhotoSettings) {

    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL, duration: CMTime, photoDisplayTime: CMTime, resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {

    }
  }

}


extension AVAuthorizationStatus {
  enum Error: Swift.Error {
    case notAuthorized
  }
  var isAuthorized: Bool {
    switch self {
    case .authorized: true
    case .notDetermined, .denied, .restricted: false
    @unknown default: false
    }
  }
}
