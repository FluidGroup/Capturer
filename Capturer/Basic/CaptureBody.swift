import AVFoundation
import Foundation

public class CaptureBody: @unchecked Sendable {

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

    public let session: AVCaptureSession

    private var inputNode: InputNodeType?
    private var outputNodes: [OutputNodeType] = []

    public init(
        configuration: Configuration
    ) {
        session = .init()
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }

        assert(Utils.checkIfCanUseCameraAccordingToPrivacySensitiveData() == true)

        session.performConfiguration {
            $0.sessionPreset = configuration.sessionPreset
            $0.automaticallyConfiguresCaptureDeviceForWideColor = true
        }

    }

    public func start() {

        Log.debug(.capture, "Session started")

        session.startRunning()
    }

    public func stop() {

        Log.debug(.capture, "Session stopped")

        session.stopRunning()
    }

    public func batchAttaching(
        input newInputNode: InputNodeType,
        outputs newOutputNodes: [OutputNodeType]
    ) {

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

    }

    /**
     Attaches an input with replacing current input.
     */
    public func attach(input newInputNode: some DeviceInputNodeType) {

        Log.debug(.capture, "Attach input \(newInputNode)")

        session.performConfiguration { session in

            if let currentNode = inputNode {
                currentNode.tearDown(sessionInConfiguring: session)
            }

            inputNode = newInputNode

            newInputNode.setUp(sessionInConfiguring: session)
        }

    }

    public func attach(output component: some OutputNodeType) {

        Log.debug(.capture, "Attach output \(component)")

        outputNodes.append(component)

        session.performConfiguration {
            component.setUp(sessionInConfiguring: $0)
        }

    }

    public func removeCurrentInput() {

        guard let currentInput = inputNode else {
            return
        }

        inputNode = nil

        session.performConfiguration {
            currentInput.tearDown(sessionInConfiguring: $0)
        }
    }

    deinit {

        Log.debug(.capture, "\(self) deinitializes")

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
