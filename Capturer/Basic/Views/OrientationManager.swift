import CoreMotion
import UIKit
import AVFoundation

public final class OrientationManager {

  public struct State: Equatable {
    public var orientation: Orientation = .init(deviceOrientaion: .portrait)
  }

  public private(set) var state: State = .init() {
    didSet {
      Log.debug(.orientation, "State changed : \(state.orientation.cgImageOrientation.rawValue)")
    }
  }

  private let manager = CMMotionManager()

  public init() {

    manager.accelerometerUpdateInterval = 0.3

    if let initialData = manager.accelerometerData {
      state.orientation = .init(deviceOrientaion: initialData.toDeviceOrientation())
    }

  }

  public func start() {
    manager.startAccelerometerUpdates(to: .main) { [weak self] (data, error) in
      guard let self = self else { return }
      guard let data = data else {
        return
      }

      let newData = Orientation(deviceOrientaion: data.toDeviceOrientation())
      if self.state.orientation != newData {
        self.state.orientation = newData
      }
      
    }
  }

  public func stop() {
    manager.stopAccelerometerUpdates()
  }

//  public func previewLayerOrientation() -> AVCaptureVideoOrientation {
//    switch UIApplication.shared.statusBarOrientation {
//    case .portrait, .unknown:
//      return .portrait
//    case .landscapeLeft:
//      return .landscapeLeft
//    case .landscapeRight:
//      return .landscapeRight
//    case .portraitUpsideDown:
//      return .portraitUpsideDown
//    @unknown default:
//      assertionFailure()
//      return .portrait
//    }
//  }

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
