import Photos
import UIKit

enum PhotoTools {

  @MainActor
  public static func save(image: UIImage, completion: @escaping (Result<Void, Error>) -> Void) {

    PHPhotoLibrary.shared().performChanges {

      PHAssetChangeRequest.creationRequestForAsset(from: image)

    } completionHandler: { success, error in

      DispatchQueue.main.async {

        if let error = error {
          completion(.failure(error))
          return
        }

        completion(.success(()))
      }

    }

  }

  @available(iOS 15.0.0, *)
  @MainActor
  static func save(image: UIImage) async throws {

    try await withCheckedThrowingContinuation { continuation in
      save(image: image) { result in
        continuation.resume(with: result)
      }
    }

  }

}
