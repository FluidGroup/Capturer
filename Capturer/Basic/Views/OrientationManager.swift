import CoreMotion
import UIKit
import AVFoundation

public final class OrientationManager {

  public struct State: Equatable {
    public var orientation: UIDeviceOrientation = .portrait

    public var cgImageOrientation: CGImagePropertyOrientation {
      orientation.toImageOrientation()
    }

    public var uiImageOrientation: UIImage.Orientation {
      return .init(orientation.toImageOrientation())
    }

    public var cgImageOrientationMirrored: CGImagePropertyOrientation {
      orientation.toImageOrientation().mirrored
    }

    public var uiImageOrientationMirrored: UIImage.Orientation {
      return .init(cgImageOrientationMirrored)
    }
  }

  public private(set) var state: State = .init() {
    didSet {
      Log.debug(.orientation, "State changed : \(state.cgImageOrientation.rawValue)")
    }
  }

  public static let shared = OrientationManager()

  private let manager = CMMotionManager()

  private init() {

    manager.accelerometerUpdateInterval = 0.3

    if let initialData = manager.accelerometerData {
      state.orientation = initialData.toDeviceOrientation()
    }

  }

  public func start() {
    manager.startAccelerometerUpdates(to: .main) { [unowned self] (data, error) in
      guard let data = data else {
        return
      }

      let newData = data.toDeviceOrientation()
      if self.state.orientation != newData {
        self.state.orientation = newData
      }
      
    }
  }

  public func stop() {
    manager.stopAccelerometerUpdates()
  }

  public func previewLayerOrientation() -> AVCaptureVideoOrientation {
    switch UIApplication.shared.statusBarOrientation {
    case .portrait, .unknown:
      return .portrait
    case .landscapeLeft:
      return .landscapeLeft
    case .landscapeRight:
      return .landscapeRight
    case .portraitUpsideDown:
      return .portraitUpsideDown
    @unknown default:
      assertionFailure()
      return .portrait
    }
  }

  deinit {
    stop()
  }

}

extension CMAccelerometerData {

  fileprivate func toDeviceOrientation() -> UIDeviceOrientation {
    if(abs(acceleration.y) < abs(acceleration.x)){
      if(acceleration.x > 0){
        return .landscapeRight
      } else {
        return .landscapeLeft
      }
    } else{
      if(acceleration.y > 0){
        return .portraitUpsideDown
      } else {
        return .portrait
      }
    }
  }

}

extension UIDeviceOrientation {

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
  init(_ uiOrientation: UIImage.Orientation) {
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
  init(_ cgOrientation: CGImagePropertyOrientation) {
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
