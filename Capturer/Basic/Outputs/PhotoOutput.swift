@preconcurrency import AVFoundation
import UIKit
import ImageIO

/**
 An output node for photo capturing.
 Use ``PreviewOutput`` for previewing in UI.
 */

public final class PhotoOutput: _StatefulObjectBase, OutputNodeType, @unchecked Sendable {

    public struct CapturePhoto: Sendable {

    public let photo: AVCapturePhoto

    public var orientation: CGImagePropertyOrientation {
      let orientationValue = photo.metadata[String(kCGImagePropertyOrientation)] as! NSNumber
      return CGImagePropertyOrientation(rawValue: orientationValue.uint32Value)!
    }

    /**
     Creates an image from captured data
     */
    public func makeImage(isMirrored: Bool) -> UIImage {
      .init(
        cgImage: photo.cgImageRepresentation()!,
        scale: 1,
        orientation: isMirrored ? orientation.uiImageOrientation.mirrored : orientation.uiImageOrientation
      )
    }

  }

  private let _output = AVCapturePhotoOutput()

  public init(quality: AVCapturePhotoOutput.QualityPrioritization = .balanced) {
    super.init()

    _output.isHighResolutionCaptureEnabled = true
    _output.maxPhotoQualityPrioritization = quality
  }

  public func capture(with settings: AVCapturePhotoSettings, completion: @escaping (Result<CapturePhoto, Error>) -> Void) {

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

  public func capture(with settings: AVCapturePhotoSettings) async throws -> CapturePhoto {
    guard AVCaptureDevice.authorizationStatus(for: .video).isAuthorized else { throw AVAuthorizationStatus.Error.notAuthorized }
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
