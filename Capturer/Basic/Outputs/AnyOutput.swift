
import Foundation
import AVFoundation

public final class AnyOutput<Downstream>: OutputNodeType {

  private let backing: OutputNodeType

  public init(_ backing: OutputNodeType) {
    self.backing = backing
  }

  public func setUp(sessionInConfiguring: AVCaptureSession) {
    backing.setUp(sessionInConfiguring: sessionInConfiguring)
  }

  public func tearDown(sessionInConfiguring: AVCaptureSession) {
    backing.tearDown(sessionInConfiguring: sessionInConfiguring)
  }

}
