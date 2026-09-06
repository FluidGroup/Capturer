import AVFoundation
import Foundation

open class PreviewOutput: VideoDataOutput, @unchecked Sendable {

  public struct State: Equatable {

    public struct InputInfo: Equatable {

      public let activeFormat: AVCaptureDevice.Format
      /// The connection's `videoRotationAngle` when the connection was formed: 0, 90, 180 or 270
      /// degrees, relative to the sensor's native orientation. On iPhones through 16 (and iPhone
      /// 17 rear cameras) 90 is portrait; the iPhone 17 front camera's sensor is mounted
      /// differently and reports 0 for portrait. The rotation coordinator installed afterwards
      /// may set a different angle on the connection; this value is not refreshed when it does.
      public let videoRotationAngle: CGFloat

      /// The connection's orientation as the enumeration iOS 17 retired.
      ///
      /// Kept for callers written against it; it is derived from `videoRotationAngle`, which is
      /// what the connection actually reports now. Assumes the classic sensor mounting
      /// (90 == portrait); see `videoRotationAngle`.
      @available(*, deprecated, message: "Use videoRotationAngle")
      public var videoOrientation: AVCaptureVideoOrientation {
        switch videoRotationAngle {
        case 90: return .portrait
        case 270: return .portraitUpsideDown
        case 180: return .landscapeLeft
        default: return .landscapeRight
        }
      }

      public var aspectRatio: CGSize {
        let dimension = CMVideoFormatDescriptionGetDimensions(activeFormat.formatDescription)
        return CGSize(width: CGFloat(dimension.width), height: CGFloat(dimension.height))
      }

      /// The format's dimensions as the rotated frames come out: a quarter turn swaps them.
      ///
      /// Until 4.4.1 this returned the reverse — unswapped at a quarter turn, swapped otherwise —
      /// which no caller had noticed because none existed. Deprecated so that a caller written
      /// against the old answer sees the change; the value is now right.
      @available(*, deprecated, message: "Use InputInfo.aspectRatio(_:rotatedBy:) with aspectRatio and videoRotationAngle")
      public var aspectRatioRespectingVideoOrientation: CGSize {
        Self.aspectRatio(aspectRatio, rotatedBy: videoRotationAngle)
      }

      /// `size` once frames have been turned by `videoRotationAngle` degrees: swapped at a
      /// quarter turn (90, 270), unchanged at 0, 180 and at any angle that is not a multiple
      /// of a quarter turn, which a connection never reports.
      public static func aspectRatio(_ size: CGSize, rotatedBy videoRotationAngle: CGFloat) -> CGSize {
        switch videoRotationAngle {
        case 90, 270:
          return CGSize(width: size.height, height: size.width)
        default:
          return size
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
        videoRotationAngle: connection.videoRotationAngle
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

  /// How far the buffers this output publishes still need turning for their horizon to be level,
  /// in degrees, or `nil` before the rotation coordinator has been installed.
  ///
  /// Uses the coordinator's *capture* angle, which comes from the device's physical orientation
  /// and needs no preview layer. The preview angle is the wrong one here: it is defined relative
  /// to a preview layer's interface orientation, and this coordinator has no layer — on an iPhone
  /// 16 Pro Max held in portrait it reported 0, which is also why the connection below ends up
  /// applying nothing. So hold the device the way the footage should read; the answer follows
  /// gravity, not the screen.
  ///
  /// It is the *remaining* rotation. This output asks its connection to rotate the buffers and a
  /// connection may refuse (`isVideoRotationAngleSupported`), in which case frames arrive in the
  /// sensor's landscape orientation with the connection reporting zero. Anything that stores or
  /// re-displays them outside the preview layer — a demo recording — must stamp the difference:
  /// stamping the full angle onto frames the connection had already turned rotates them twice.
  public var rotationAngleForUprightFrames: CGFloat? {
    let (coordinator, connection) = rotationLock.withLock {
      (rotationCoordinator, rotationConnection)
    }
    guard let coordinator else { return nil }
    return Self.rotationNeeded(
      horizonAngle: coordinator.videoRotationAngleForHorizonLevelCapture,
      connectionAngle: connection?.videoRotationAngle ?? 0
    )
  }

  /// The rotation left to apply once a connection has applied `connectionAngle` of the
  /// `horizonAngle` the frames need, normalised to `0..<360`.
  static func rotationNeeded(horizonAngle: CGFloat, connectionAngle: CGFloat) -> CGFloat {
    let remainder = (horizonAngle - connectionAngle).truncatingRemainder(dividingBy: 360)
    return remainder < 0 ? remainder + 360 : remainder
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
