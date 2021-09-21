
import Foundation
import AVFoundation
import MetalKit

public final class VideoDataOutput: OutputComponentType {

  struct Handlers {
    var didOutput: (CMSampleBuffer) -> Void = { _ in }
  }

  private let _output = AVCaptureVideoDataOutput()

  private let delegateProxy = _AVCaptureVideoDataOutputSampleBufferDelegateProxy()

  public let sampleBufferBus: EventBus<CMSampleBuffer> = .init()

  public init() {

    let queue = DispatchQueue(label: "VideoDataOutputComponent")

    _output.setSampleBufferDelegate(delegateProxy, queue: queue)

    delegateProxy.handlers.didOutput = { [sampleBufferBus] sampleBuffer in
      sampleBufferBus.emit(event: sampleBuffer)
    }
  }

  public func setUp(sessionInConfiguring: AVCaptureSession) {
    sessionInConfiguring.addOutput(_output)
    // TODO: handles connections with better way
    assert(_output.connections.count == 1)
    _output.connections.first?.videoOrientation = .portrait
  }

  public func tearDown(sessionInConfiguring: AVCaptureSession) {
    sessionInConfiguring.removeOutput(_output)
  }

  private final class _AVCaptureVideoDataOutputSampleBufferDelegateProxy: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    var handlers: Handlers = .init()

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {

    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
      handlers.didOutput(sampleBuffer)
    }

  }

}
