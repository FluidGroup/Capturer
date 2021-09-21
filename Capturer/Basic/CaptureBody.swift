
import Foundation
import AVFoundation

public final class CaptureBody {

  public let session: AVCaptureSession

  private var inputComponent: InputComponentType?
  private var outputComponents: [OutputComponentType] = []

  private let configurationQueue = DispatchQueue(label: "CameraBody")

  public init() {
    session = .init()
    assert(Utils.checkIfCanUseCameraAccordingToPrivacySensitiveData() == true)

    session.performConfiguration {
      $0.sessionPreset = .photo
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

  public func attach(input component: InputComponentType) {

    Log.debug(.capture, "Attach input \(component)")

    // TODO: guard attaching multiple inputs

    configurationQueue.sync {
      inputComponent = component

      session.performConfiguration {
        component.setUp(sessionInConfiguring: $0)
      }
    }
  }

  public func attach(output component: OutputComponentType) {

    Log.debug(.capture, "Attach output \(component)")

    configurationQueue.sync {
      outputComponents.append(component)

      session.performConfiguration {
        component.setUp(sessionInConfiguring: $0)
      }
    }
  }

  public func removeCurrentInput() {

    guard let currentInput = inputComponent else {
      return
    }

    inputComponent = nil

    configurationQueue.sync {
      session.performConfiguration {
        currentInput.tearDown(sessionInConfiguring: $0)
      }
    }
  }

  deinit {

    Log.debug(.capture, "\(self) deinitializes")

    removeCurrentInput()

    configurationQueue.sync { 
      session.performConfiguration { session in
        outputComponents.forEach { output in
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
