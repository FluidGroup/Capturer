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

    public struct InputInfo: Equatable {

      public let activeFormat: AVCaptureDevice.Format

      public var aspectRatio: CGSize {
        let dimension = CMVideoFormatDescriptionGetDimensions(activeFormat.formatDescription)
        return CGSize(width: CGFloat(dimension.width), height: CGFloat(dimension.height))
      }
    }

    public var inputInfo: InputInfo?

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

  private var activeFormatObservation: NSKeyValueObservation?

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
  public func attach<Node: DeviceInputNodeType>(input newInputNode: Node) {

    Log.debug(.capture, "Attach input \(newInputNode)")

    configurationQueue.sync {

      session.performConfiguration { session in

        if let currentNode = inputNode {
          currentNode.tearDown(sessionInConfiguring: session)
        }

        inputNode = newInputNode

        newInputNode.setUp(sessionInConfiguring: session)
      }

      activeFormatObservation?.invalidate()
      activeFormatObservation = newInputNode.device.observe(\.activeFormat, options: [.initial, .new]) { [weak self] _, c in
        self?.state.inputInfo = c.newValue.map { .init(activeFormat: $0) }
      }
    }

  }

  @MainActor
  public func attach<Node: OutputNodeType>(output component: Node) {

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

    activeFormatObservation?.invalidate()

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
