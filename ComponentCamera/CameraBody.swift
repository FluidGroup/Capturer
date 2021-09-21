//
//  Tmp.swift
//  ComponentCamera
//
//  Created by muukii on 2020/10/12.
//

import Foundation
import AVFoundation

public final class CameraBody {

  public let session: AVCaptureSession

  private var inputComponent: InputComponentType?
  private var outputComponent: OutputComponentType?

  private let configurationQueue = DispatchQueue(label: "CameraBody")

  public init() {

    session = .init()

    assert(Utils.checkIfCanUseCameraAccordingToPrivacySensitiveData() == true)

    let discoverySession = AVCaptureDevice.DiscoverySession(
      deviceTypes: [
        .builtInWideAngleCamera,
      ], mediaType: .video,
      position: .back
    )

    let input = try! AVCaptureDeviceInput(device: discoverySession.devices.first!)

    session.performConfiguration {
      $0.sessionPreset = .high
      $0.addInput(input)
    }

    session.startRunning()
  }

  public func start() {
    session.startRunning()
  }

  public func stop() {
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

}


extension AVCaptureSession {

  func performConfiguration(_ perform: (AVCaptureSession) -> Void) {
    beginConfiguration()
    defer {
      commitConfiguration()
    }
    perform(self)
  }

}
