import AVFoundation
import UIKit

/**
 An output node for photo capturing.
 Use ``PreviewOutput`` for previewing in UI.
 */
public final class PhotoOutput: _StatefulObjectBase, OutputNodeType {

  public struct CapturePhoto {

    public let photo: AVCapturePhoto
    public let preferredOrientation: Orientation

    /**
     Creates an image from captured data with current device orientation.
     */
    public func makeOrientationFixedImage(isMirrored: Bool) -> UIImage {
      .init(
        cgImage: photo.cgImageRepresentation()!,
        scale: 1,
        orientation: isMirrored ? preferredOrientation.uiImageOrientationMirrored : preferredOrientation.uiImageOrientation
      )
    }

  }

  private let _output = AVCapturePhotoOutput()

  public let orientationManager = OrientationManager()

  public override init() {
    super.init()

    _output.isHighResolutionCaptureEnabled = true
  }

  public func makeCaptureSettings() -> AVCapturePhotoSettings {

    let settings = AVCapturePhotoSettings()

    /// deprecated from iOS 13
    settings.isAutoStillImageStabilizationEnabled = true
    settings.isHighResolutionPhotoEnabled = true

    return settings
  }

  public func capture(with settings: AVCapturePhotoSettings, completion: @escaping (Result<CapturePhoto, Error>) -> Void) {

    var completionWrapper: ((Result<CapturePhoto, Error>) -> Void)!

    let orientation = orientationManager.state.orientation

    let proxy = _AVCapturePhotoCaptureDelegateProxy { photo, error in
      if let error = error {
        completionWrapper(.failure(error))
        return
      }
      completionWrapper(.success(.init(photo: photo, preferredOrientation: orientation)))
    }

    completionWrapper = {
      completion($0)
      withExtendedLifetime(proxy, {})
    }

    _output.capturePhoto(with: settings, delegate: proxy)

  }

  @available(iOS 15.0.0, *)
  public func capture(with settings: AVCapturePhotoSettings) async throws -> CapturePhoto {
    try await withCheckedThrowingContinuation { continuation in
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
    orientationManager.start()
    sessionInConfiguring.addOutput(_output)
  }

  public func tearDown(sessionInConfiguring: AVCaptureSession) {
    orientationManager.stop()
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
