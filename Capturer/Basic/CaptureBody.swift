
import Foundation
import AVFoundation

public final class CaptureBody {

  public let session: AVCaptureSession

  private var inputComponent: InputComponentType?
  private var outputComponent: OutputComponentType?

  private let configurationQueue = DispatchQueue(label: "CameraBody")

  public init() {
    session = .init()
    assert(Utils.checkIfCanUseCameraAccordingToPrivacySensitiveData() == true)
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

    configurationQueue.sync {
      inputComponent = component

      session.performConfiguration {
        component.setUp(sessionInConfiguring: $0)
      }
    }
  }

  public func attach(output component: OutputComponentType) {

    configurationQueue.sync {
      outputComponent = component

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

  public func removeCurrentOutput() {

    guard let currentOutput = outputComponent else {
      return
    }

    outputComponent = nil

    configurationQueue.sync {
      session.performConfiguration {
        currentOutput.tearDown(sessionInConfiguring: $0)
      }
    }
  }

  deinit {

    Log.debug(.capture, "\(self) deinitializes")

    removeCurrentInput()
    removeCurrentOutput()

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
