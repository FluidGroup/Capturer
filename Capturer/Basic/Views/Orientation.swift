import AVFoundation
import Foundation
import UIKit

public struct Orientation: Equatable {

  public let cgImagePropertyOrientation: CGImagePropertyOrientation

  public var deviceOrientation: UIDeviceOrientation {
    return .init(cgImagePropertyOrientation)
  }

  public var cgImageOrientation: CGImagePropertyOrientation {
    deviceOrientation.toImageOrientation()
  }

  public var uiImageOrientation: UIImage.Orientation {
    return .init(deviceOrientation.toImageOrientation())
  }

  public var cgImageOrientationMirrored: CGImagePropertyOrientation {
    deviceOrientation.toImageOrientation().mirrored
  }

  public var uiImageOrientationMirrored: UIImage.Orientation {
    return .init(cgImageOrientationMirrored)
  }

  public init(
    deviceOrientaion: UIDeviceOrientation
  ) {
    self.init(primitiveValue: deviceOrientaion.toImageOrientation())
  }

  public init(
    cgImagePropertyOrientation: CGImagePropertyOrientation
  ) {
    self.init(primitiveValue: cgImagePropertyOrientation)
  }

  public init(
    uiImageOrientation: UIImage.Orientation
  ) {
    self.init(primitiveValue: .init(uiImageOrientation))
  }

  public init(
    captureVideoOrientation: AVCaptureVideoOrientation
  ) {
    self.init(primitiveValue: .init(captureVideoOrientation))
  }

  private init(
    primitiveValue: CGImagePropertyOrientation
  ) {
    self.cgImagePropertyOrientation = primitiveValue
  }

  public func applying(to size: CGSize) -> CGSize {
    switch cgImagePropertyOrientation {
    case .up, .upMirrored, .down, .downMirrored:
      return size
    case .left, .leftMirrored, .right, .rightMirrored:
      return .init(width: size.height, height: size.width)
    }
  }

}

extension UIDeviceOrientation {

  init(
    _ cgImagePropertyOrientation: CGImagePropertyOrientation
  ) {
    switch cgImagePropertyOrientation {
    case .up:
      self = .landscapeLeft
    case .down:
      self = .landscapeRight
    case .left:
      self = .portraitUpsideDown
    case .right:
      self = .portrait
    case .upMirrored:
      self = .landscapeLeft
    case .downMirrored:
      self = .landscapeRight
    case .leftMirrored:
      self = .portraitUpsideDown
    case .rightMirrored:
      self = .portrait
    }
  }

  fileprivate func toImageOrientation() -> CGImagePropertyOrientation {

    switch self {
    case .landscapeLeft:
      return .up
    case .landscapeRight:
      return .down
    case .portraitUpsideDown:
      return .left
    case .unknown:
      return .right
    case .portrait:
      return .right
    case .faceUp:
      return .right
    case .faceDown:
      return .right
    @unknown default:
      return .right
    }

  }

}

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
    }
  }
}

extension UIImage.Orientation {
  init(
    _ cgOrientation: CGImagePropertyOrientation
  ) {
    switch cgOrientation {
    case .up: self = .up
    case .upMirrored: self = .upMirrored
    case .down: self = .down
    case .downMirrored: self = .downMirrored
    case .left: self = .left
    case .leftMirrored: self = .leftMirrored
    case .right: self = .right
    case .rightMirrored: self = .rightMirrored
    }
  }
}
