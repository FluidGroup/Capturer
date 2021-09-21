
import Foundation
import AVFoundation
import MetalKit

public final class VideoDataOutput: _StatefulObjectBase, OutputComponentType {

  struct Handlers {
    var didOutput: (CMSampleBuffer) -> Void = { _ in }
  }

  private let _output = AVCaptureVideoDataOutput()

  private let delegateProxy = _AVCaptureVideoDataOutputSampleBufferDelegateProxy()

  public let sampleBufferBus: EventBus<CMSampleBuffer> = .init()

  private var observation: NSKeyValueObservation?

  public override init() {

    let queue = DispatchQueue(label: "VideoDataOutputComponent")

    _output.setSampleBufferDelegate(delegateProxy, queue: queue)

    delegateProxy.handlers.didOutput = { [sampleBufferBus] sampleBuffer in
      sampleBufferBus.emit(event: sampleBuffer)
    }

    observation = _output.observe(\.connections, options: [.initial, .new]) { output, changes in
      print(output.connections)

      // TODO: handles connections with better way
      if let firstConnection = output.connections.first {
        firstConnection.videoOrientation = .portrait
      } else {

      }

    }
  }

  public func setUp(sessionInConfiguring: AVCaptureSession) {
    sessionInConfiguring.addOutput(_output)
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
