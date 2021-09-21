
import Foundation
import AVFoundation

public final class AnyCMSampleBufferOutput: _StatefulObjectBase, OutputComponentType {

  public var sampleBufferBus: EventBus<CMSampleBuffer> {
    backing.sampleBufferBus
  }

  private let backing: VideoDataOutput

  public init(_ backing: VideoDataOutput) {
    self.backing = backing
  }

  public func setUp(sessionInConfiguring: AVCaptureSession) {
    backing.setUp(sessionInConfiguring: sessionInConfiguring)
  }

  public func tearDown(sessionInConfiguring: AVCaptureSession) {
    backing.tearDown(sessionInConfiguring: sessionInConfiguring)
  }

}
