import AVFoundation
import Foundation

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

  /// Guards the rotation state below.
  ///
  /// `didChange(connections:)` runs on whichever thread reconfigured the session, while the
  /// coordinator is built and installed on the main actor, so these really are shared.
  private let rotationLock = NSLock()

  /// Rotation coordinator that reports the correct rotation angle for the current
  /// physical device orientation.
  private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
  private var rotationObservation: NSKeyValueObservation?
  private weak var rotationConnection: AVCaptureConnection?

  /// Identifies the most recent `didChange(connections:)`, so a main-actor hop that has
  /// been superseded by a newer reconfiguration discards its coordinator instead of
  /// installing it over the current one.
  private var rotationGeneration: UInt64 = 0

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

    // Tear down any prior rotation observation before reconfiguring, and claim the
    // generation that the resulting coordinator must still match to be installed.
    //
    // The observation is handed back out and invalidated *after* the lock is released.
    // `invalidate()` calls `removeObserver`, which blocks until any notification already
    // in flight for that coordinator finishes — and that notification's block takes this
    // same lock to resolve its connection. Invalidating while holding the lock would
    // deadlock the two against each other. Clearing the state and bumping the generation
    // is enough on its own: an in-flight block finds a generation mismatch and does
    // nothing.
    let (previousObservation, generation) = rotationLock.withLock {
      () -> (NSKeyValueObservation?, UInt64) in
      let previous = rotationObservation
      rotationObservation = nil
      rotationCoordinator = nil
      rotationConnection = nil
      rotationGeneration &+= 1
      return (previous, rotationGeneration)
    }
    previousObservation?.invalidate()

    if let connection = proposedConnection,
       let device = (connection.inputPorts.first?.input as? AVCaptureDeviceInput)?.device {

      installRotationCoordinator(
        device: device,
        connection: connection,
        generation: generation
      )

      let activeFormat = device.activeFormat

      self.state.inputInfo = .init(
        activeFormat: activeFormat,
        videoOrientation: connection.videoOrientation
      )
    } else {
      self.state.inputInfo = nil
    }

  }

  /// Builds the rotation coordinator on the main actor, asynchronously.
  ///
  /// `AVCaptureDevice.RotationCoordinator.init` blocks internally on the main queue — it
  /// does so even when `previewLayer` is `nil`. `didChange(connections:)` is delivered
  /// synchronously by KVO from inside `-[AVCaptureSession addOutput:]`, which means the
  /// caller is holding the session's lock. Building the coordinator there deadlocks
  /// against any main-thread code waiting on that same session lock — reading
  /// `AVCaptureSession.inputs`, for instance — because the configuring thread cannot
  /// release the lock until the main queue drains, and the main queue cannot drain until
  /// it acquires the lock.
  ///
  /// Hopping asynchronously breaks the cycle: the configuration block completes and drops
  /// the session lock, and only then is the main queue needed.
  private func installRotationCoordinator(
    device: AVCaptureDevice,
    connection: AVCaptureConnection,
    generation: UInt64
  ) {

    let boxedDevice = UncheckedSendable(device)
    let boxedConnection = UncheckedSendable(connection)

    Task { @MainActor [weak self] in

      guard let self else { return }

      let connection = boxedConnection.wrapped

      // Track the device's physical rotation via AVCaptureDevice.RotationCoordinator.
      // This works correctly across iPhone/iPad orientations.
      let coordinator = AVCaptureDevice.RotationCoordinator(
        device: boxedDevice.wrapped,
        previewLayer: nil
      )

      let observation = coordinator.observe(
        \.videoRotationAngleForHorizonLevelPreview,
        options: [.new]
      ) { [weak self] _, change in
        guard let self,
              let newAngle = change.newValue,
              let target = self.rotationConnection(matching: generation) else { return }
        self.applyRotationAngle(newAngle, to: target)
      }

      let isCurrent = self.rotationLock.withLock { () -> Bool in
        guard generation == self.rotationGeneration else { return false }
        self.rotationCoordinator = coordinator
        self.rotationObservation = observation
        self.rotationConnection = connection
        return true
      }

      guard isCurrent else {
        // A newer didChange(connections:) landed while this hop was in flight; that one
        // owns the rotation state now.
        observation.invalidate()
        return
      }

      self.applyRotationAngle(
        coordinator.videoRotationAngleForHorizonLevelPreview,
        to: connection
      )
    }
  }

  /// The connection the given generation is still allowed to drive, or `nil` once a newer
  /// reconfiguration has taken over.
  private func rotationConnection(matching generation: UInt64) -> AVCaptureConnection? {
    rotationLock.withLock {
      generation == rotationGeneration ? rotationConnection : nil
    }
  }

  private func applyRotationAngle(_ angle: CGFloat, to connection: AVCaptureConnection) {
    if connection.isVideoRotationAngleSupported(angle) {
      connection.videoRotationAngle = angle
    }
  }

}
