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

    // TODO: handles connections with better way
    if let connection = proposedConnection {

      connection.videoOrientation = .portrait

      let activeFormat = (connection.inputPorts.first!.input as! AVCaptureDeviceInput).device.activeFormat

      self.state.inputInfo = .init(
        activeFormat: activeFormat,
        videoOrientation: connection.videoOrientation
      )
    } else {
      self.state.inputInfo = nil
    }

  }

}
