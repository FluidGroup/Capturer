import AVFoundation
import Foundation


// to be replaced by the wrapped CaptureBody once ios 18.4 availability allow us to use isolated deinit.
public typealias CaptureBody = CaptureBodyWrapper

public final class CaptureBodyWrapper: @unchecked Sendable {
  public typealias Configuration = CaptureBody.Configuration

  public actor CaptureBody {

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

    private let session: AVCaptureSession = .init()
    private var inputNode: InputNodeType?
    private var outputNodes: [OutputNodeType] = []

    public init(
      configuration: Configuration
    ) {
      guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
      _ = self.session

      assert(Utils.checkIfCanUseCameraAccordingToPrivacySensitiveData() == true)

      self.session.performConfiguration {
        $0.sessionPreset = configuration.sessionPreset
        $0.automaticallyConfiguresCaptureDeviceForWideColor = true
      }

    }

    public func start() {
      Log.debug(.capture, "Session started")

      self.session.startRunning()
    }

    public func stop() {

      Log.debug(.capture, "Session stopped")
      self.session.stopRunning()
    }

    public func batchAttaching(
      input newInputNode: InputNodeType,
      outputs newOutputNodes: [OutputNodeType]
    ) {
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

    /**
     Attaches an input with replacing current input.
     */
    public func attach(input newInputNode: some DeviceInputNodeType) {

      Log.debug(.capture, "Attach input \(newInputNode)")

      self.session.performConfiguration { session in

        if let currentNode = self.inputNode {
          currentNode.tearDown(sessionInConfiguring: session)
        }

        self.inputNode = newInputNode

        newInputNode.setUp(sessionInConfiguring: session)
      }
    }

    public func attach(output component: some OutputNodeType) {

      Log.debug(.capture, "Attach output \(component)")

      outputNodes.append(component)


      self.session.performConfiguration {
        component.setUp(sessionInConfiguring: $0)
      }
    }

    public func removeCurrentInput() {

      guard let currentInput = inputNode else {
        return
      }

      inputNode = nil

      self.session.performConfiguration {
        currentInput.tearDown(sessionInConfiguring: $0)
      }
    }

    // upon migrating to ios 18.4, we can place this in the isolated deinit and remove the wrapper calling it
    fileprivate func isolatedDeinitAction() {
      session.performConfiguration { [inputNode] in
        inputNode?.tearDown(sessionInConfiguring: $0)
      }

      session.performConfiguration { [outputNodes] session in
        outputNodes.forEach { output in
          output.tearDown(sessionInConfiguring: session)
        }
      }
    }

    deinit {

      Log.debug(.capture, "\(self) deinitializes")

    }

  }

  // Boilerplate wrapping:
  public init(
    configuration: Configuration
  ) {
    self.wrappedCaptureBody = .init(configuration: configuration)
  }

  public func start() async {
    await wrappedCaptureBody.start()
  }

  public func stop() async {
    await wrappedCaptureBody.stop()
  }

  public func batchAttaching(
    input newInputNode: InputNodeType,
    outputs newOutputNodes: [OutputNodeType]
  ) async {
    await wrappedCaptureBody.batchAttaching(input: newInputNode, outputs: newOutputNodes)
  }

  public func removeCurrentInput() async {
    await wrappedCaptureBody.removeCurrentInput()
  }

  public func attach(output component: some OutputNodeType) async {
    await wrappedCaptureBody.attach(output: component)
  }

  public func attach(input newInputNode: some DeviceInputNodeType) async {
    await wrappedCaptureBody.attach(input: newInputNode)
  }

  private let wrappedCaptureBody: CaptureBody

  deinit {
    Task { [wrappedCaptureBody] in
      await wrappedCaptureBody.isolatedDeinitAction()
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
