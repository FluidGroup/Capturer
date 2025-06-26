import AVFoundation
import Foundation


// Can't be easily made into an actor do to the deinit. Maybe if the min framework is 18.4 we can move to an actor
public final class CaptureBody: @unchecked Sendable {
  private let backgroundExecutionQueue = DispatchQueue(label: "Capturer.CaptureBody.backgroundExecutionQueue", qos: .userInitiated)

  public struct Configuration: Sendable {

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

  private lazy var session: AVCaptureSession = {
    backgroundExecutionQueue.sync {
      .init()
    }
  }()

  private var inputNode: InputNodeType?
  private var outputNodes: [OutputNodeType] = []

  public init(
    configuration: Configuration
  ) {
    guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
    _ = self.session

    assert(Utils.checkIfCanUseCameraAccordingToPrivacySensitiveData() == true)
    backgroundExecutionQueue.async {

      self.session.performConfiguration {
        $0.sessionPreset = configuration.sessionPreset
        $0.automaticallyConfiguresCaptureDeviceForWideColor = true
      }
    }

  }

  public func start() {

    Log.debug(.capture, "Session started")

    backgroundExecutionQueue.async {
      self.session.startRunning()
    }
  }

  public func stop() {

    Log.debug(.capture, "Session stopped")
    backgroundExecutionQueue.async {
      self.session.stopRunning()
    }
  }

  public func batchAttaching(
    input newInputNode: InputNodeType,
    outputs newOutputNodes: [OutputNodeType]
  ) {

    backgroundExecutionQueue.async {

      self.session.performConfiguration { session in

        if let currentInputNode = self.inputNode {
          currentInputNode.tearDown(sessionInConfiguring: session)
        }

        self.inputNode = newInputNode

        newInputNode.setUp(sessionInConfiguring: session)

        self.outputNodes.append(contentsOf: newOutputNodes)

        session.performConfiguration { session in
          newOutputNodes.forEach {
            $0.setUp(sessionInConfiguring: session)
          }
        }
      }
    }

  }

  /**
   Attaches an input with replacing current input.
   */
  public func attach(input newInputNode: some DeviceInputNodeType) {

    Log.debug(.capture, "Attach input \(newInputNode)")
    backgroundExecutionQueue.async {

      self.session.performConfiguration { session in

        if let currentNode = self.inputNode {
          currentNode.tearDown(sessionInConfiguring: session)
        }

        self.inputNode = newInputNode

        newInputNode.setUp(sessionInConfiguring: session)
      }
    }
  }

  public func attach(output component: some OutputNodeType) {

    Log.debug(.capture, "Attach output \(component)")

    outputNodes.append(component)

    backgroundExecutionQueue.async {

      self.session.performConfiguration {
        component.setUp(sessionInConfiguring: $0)
      }
    }
  }

  public func removeCurrentInput() {

    guard let currentInput = inputNode else {
      return
    }

    inputNode = nil

    backgroundExecutionQueue.async {

      self.session.performConfiguration {
        currentInput.tearDown(sessionInConfiguring: $0)
      }
    }
  }

  deinit {

    Log.debug(.capture, "\(self) deinitializes")


    backgroundExecutionQueue.async { [inputNode, outputNodes, session] in

      session.performConfiguration { [inputNode] in
        inputNode?.tearDown(sessionInConfiguring: $0)
      }

      session.performConfiguration { [outputNodes] session in
        outputNodes.forEach { output in
          output.tearDown(sessionInConfiguring: session)
        }
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
