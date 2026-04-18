import AVFoundation

open class PreviewOutput: VideoDataOutput, @unchecked Sendable {

  public struct State: Equatable {

    public struct InputInfo: Equatable {

      public let activeFormat: AVCaptureDevice.Format
      public let videoOrientation: AVCaptureVideoOrientation

      public var aspectRatio: CGSize {
        let dimension = CMVideoFormatDescriptionGetDimensions(activeFormat.formatDescription)
        return CGSize(width: CGFloat(dimension.width), height: CGFloat(dimension.height))
      }

      /**
       Aspect ratio described using CGSize that applied orientation.
       Normally, camera's top is the left side of the device.
       */
      public var aspectRatioRespectingVideoOrientation: CGSize {
        switch videoOrientation {
        case .portrait, .portraitUpsideDown:
          return aspectRatio
        case .landscapeLeft, .landscapeRight:
          return .init(width: aspectRatio.height, height: aspectRatio.width)
        @unknown default:
          return aspectRatio
        }
      }
    }

    public var inputInfo: InputInfo?

  }

  public private(set) var state: State = .init()

  /// Rotation coordinator that reports the correct rotation angle for the current
  /// physical device orientation.
  private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
  private var rotationObservation: NSKeyValueObservation?
  private weak var rotationConnection: AVCaptureConnection?

  open override func didChange(connections: [AVCaptureConnection]) {

    assert(connections.count <= 1)

    #if DEBUG

    for connection in connections {
      Log.debug(.capture, "Connection: \(connection._capturer_debuggingInfo())")
    }

    #endif

    let proposedConnection = connections
      .lazy
      .filter {
        $0.inputPorts.contains {
          $0.mediaType == .video
        }
      }
      .first

    // Tear down any prior rotation observation before reconfiguring.
    rotationObservation?.invalidate()
    rotationObservation = nil
    rotationCoordinator = nil
    rotationConnection = nil

    if let connection = proposedConnection,
       let device = (connection.inputPorts.first?.input as? AVCaptureDeviceInput)?.device {
      // Track the device's physical rotation via AVCaptureDevice.RotationCoordinator.
      // This works correctly across iPhone/iPad orientations.
      let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
      rotationCoordinator = coordinator
      rotationConnection = connection

      applyRotationAngle(coordinator.videoRotationAngleForHorizonLevelPreview, to: connection)

      rotationObservation = coordinator.observe(
        \.videoRotationAngleForHorizonLevelPreview,
        options: [.new]
      ) { [weak self] _, change in
        guard let newAngle = change.newValue,
              let connection = self?.rotationConnection else { return }
        self?.applyRotationAngle(newAngle, to: connection)
      }

      let activeFormat = device.activeFormat

      self.state.inputInfo = .init(
        activeFormat: activeFormat,
        videoOrientation: connection.videoOrientation
      )
    } else {
      self.state.inputInfo = nil
    }

  }

  private func applyRotationAngle(_ angle: CGFloat, to connection: AVCaptureConnection) {
    if connection.isVideoRotationAngleSupported(angle) {
      connection.videoRotationAngle = angle
    }
  }

}
