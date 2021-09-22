import AVFoundation
import Foundation

public final class CaptureBody {

  public struct Configuration {

    public var sessionPreset: AVCaptureSession.Preset = .photo

    public init() {

    }

    public init(modify: (inout Self) -> Void) {
      var instance = Self()
      modify(&instance)
      self = instance
    }
  }

  public let session: AVCaptureSession

  private var inputNode: InputNodeType?
  private var outputNodes: [OutputNodeType] = []

  private let configurationQueue = DispatchQueue(label: "CameraBody")

  @MainActor
  public init(
    configuration: Configuration
  ) {
    session = .init()
    assert(Utils.checkIfCanUseCameraAccordingToPrivacySensitiveData() == true)

    session.performConfiguration {
      $0.sessionPreset = configuration.sessionPreset
    }
  }

  @MainActor
  public func start() {

    Log.debug(.capture, "Session started")

    session.startRunning()
  }

  @MainActor
  public func stop() {

    Log.debug(.capture, "Session stopped")

    session.stopRunning()
  }

  /**
   Attaches an input with replacing current input.
   */
  @MainActor
  public func attach(input newInputNode: InputNodeType) {

    Log.debug(.capture, "Attach input \(newInputNode)")

    configurationQueue.sync {

      session.performConfiguration { session in

        if let currentNode = inputNode {
          currentNode.tearDown(sessionInConfiguring: session)
        }

        inputNode = newInputNode

        newInputNode.setUp(sessionInConfiguring: session)
      }
    }

  }

  @MainActor
  public func attach(output component: OutputNodeType) {

    Log.debug(.capture, "Attach output \(component)")

    configurationQueue.sync {
      outputNodes.append(component)

      session.performConfiguration {
        component.setUp(sessionInConfiguring: $0)
      }
    }
  }

  @MainActor
  public func removeCurrentInput() {

    guard let currentInput = inputNode else {
      return
    }

    inputNode = nil

    configurationQueue.sync {
      session.performConfiguration {
        currentInput.tearDown(sessionInConfiguring: $0)
      }
    }
  }

  deinit {

    Log.debug(.capture, "\(self) deinitializes")

    session.performConfiguration {
      inputNode?.tearDown(sessionInConfiguring: $0)
    }

    session.performConfiguration { session in
      outputNodes.forEach { output in
        output.tearDown(sessionInConfiguring: session)
      }
    }

  }

}

extension AVCaptureSession {

  @inline(__always)
  func performConfiguration(_ perform: (AVCaptureSession) -> Void) {
    beginConfiguration()
    defer {
      commitConfiguration()
    }
    perform(self)
  }

}
