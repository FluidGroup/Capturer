
import Foundation
import AVFoundation

open class MapOutput<Upstream, Downstream>: OutputNodeType {

  open func perform(upstream: Upstream) -> Downstream {
    fatalError("Must be override")
  }

  public func setUp(sessionInConfiguring: AVCaptureSession) {

  }

  public func tearDown(sessionInConfiguring: AVCaptureSession) {

  }
}
