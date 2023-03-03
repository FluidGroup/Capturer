import AVFoundation
import Foundation

public final class CaptureBody {

  public struct Configuration {

    public var sessionPreset: AVCaptureSession.Preset = .photo

    public init() {

    }

    public init(
      modify: (inout Self) -> Void
    ) {
      var instance = Self()
      modify(&instance)
      self = instance
    }
  }

  public struct State: Equatable {

  }

  public struct Handlers {

    public var didChangeState: (State) -> Void = { _ in }

    public init() {}
  }

  public private(set) var state: State = .init() {
    didSet {
      if oldValue != state {
        handlers.didChangeState(state)
      }
    }
  }

  public var handlers: Handlers = .init()

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
      $0.automaticallyConfiguresCaptureDeviceForWideColor = true
    }

  }

  @MainActor
  public func start() {

    Log.debug(.capture, "Session started")

    configurationQueue.sync {
      session.startRunning()
    }
  }

  @MainActor
  public func stop() {

    Log.debug(.capture, "Session stopped")

    configurationQueue.sync {
      session.stopRunning()
    }
  }

  public func batchAttaching(
    input newInputNode: InputNodeType,
    outputs newOutputNodes: [OutputNodeType],
    completion: @escaping () -> Void
  ) {

    configurationQueue.async { [self] in

      session.performConfiguration { session in

        if let currentInputNode = inputNode {
          currentInputNode.tearDown(sessionInConfiguring: session)
        }

        inputNode = newInputNode

        newInputNode.setUp(sessionInConfiguring: session)

        outputNodes.append(contentsOf: newOutputNodes)

        session.performConfiguration { session in
          newOutputNodes.forEach {
            $0.setUp(sessionInConfiguring: session)
          }
        }

      }

      DispatchQueue.main.async {
        completion()
      }

    }

  }

  /**
   Attaches an input with replacing current input.
   */
  public func attach<Node: DeviceInputNodeType>(input newInputNode: Node, completion: @escaping () -> Void) {

    Log.debug(.capture, "Attach input \(newInputNode)")

    configurationQueue.async { [self] in

      session.performConfiguration { session in

        if let currentNode = inputNode {
          currentNode.tearDown(sessionInConfiguring: session)
        }

        inputNode = newInputNode

        newInputNode.setUp(sessionInConfiguring: session)
      }

      DispatchQueue.main.async {
        completion()
      }
    }

  }

  public func attach<Node: DeviceInputNodeType>(input newInputNode: Node) async {
    await withCheckedContinuation { c in
      attach(input: newInputNode) {
        c.resume()
      }
    }
  }

  public func attach<Node: OutputNodeType>(output component: Node, completion: @escaping () -> Void) {

    Log.debug(.capture, "Attach output \(component)")

    configurationQueue.async { [self] in
      outputNodes.append(component)

      session.performConfiguration {
        component.setUp(sessionInConfiguring: $0)
      }

      DispatchQueue.main.async {
        completion()
      }
    }
  }
  
  public func attach<Node: OutputNodeType>(output component: Node) async {
    await withCheckedContinuation { c in
      attach(output: component) {
        c.resume()
      }
    }
  }

  public func removeCurrentInput() {

    configurationQueue.async { [self] in

      guard let currentInput = inputNode else {
        return
      }

      inputNode = nil

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
