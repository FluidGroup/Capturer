import AVFoundation
import Foundation
import UIKit

extension CGImagePropertyOrientation {

  init(
    _ videoOrientation: AVCaptureVideoOrientation
  ) {
    switch videoOrientation {
    case .portrait:
      self = .right
    case .portraitUpsideDown:
      self = .left
    case .landscapeRight:
      self = .down
    case .landscapeLeft:
      self = .up
    @unknown default:
      fatalError()
    }
  }

  init(
    _ uiOrientation: UIImage.Orientation
  ) {
    switch uiOrientation {
    case .up: self = .up
    case .upMirrored: self = .upMirrored
    case .down: self = .down
    case .downMirrored: self = .downMirrored
    case .left: self = .left
    case .leftMirrored: self = .leftMirrored
    case .right: self = .right
    case .rightMirrored: self = .rightMirrored
    @unknown default:
      fatalError()
    }
  }
}

extension UIImage.Orientation {
  var mirrored: Self {
    switch self {
    case .up: return .downMirrored
    case .upMirrored: return .down
    case .down: return .upMirrored
    case .downMirrored: return .up
    case .left: return .rightMirrored
    case .leftMirrored: return .right
    case .right: return .leftMirrored
    case .rightMirrored: return .left
    @unknown default:
      return self
    }
  }
}

extension CGImagePropertyOrientation {
  var uiImageOrientation: UIImage.Orientation {
    switch self {
    case .down:
      return .down
    case .downMirrored:
      return .downMirrored
    case .left:
      return .left
    case .leftMirrored:
      return .leftMirrored
    case .right:
      return .right
    case .rightMirrored:
      return .rightMirrored
    case .up:
      return .up
    case .upMirrored:
      return .upMirrored
    }
  }
}
