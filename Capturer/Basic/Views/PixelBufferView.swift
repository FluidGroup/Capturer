
import Foundation
import UIKit
import AVFoundation

public final class PixelBufferView: UIView, PixelBufferDisplaying {

  public override init(frame: CGRect) {
    super.init(frame: frame)

    layer.contentsGravity = .resizeAspect
  }

  private var subscription: EventBusCancellable?
  /// The slot the current subscription hands frames through.
  private var pendingFrame: LatestValueSlot<CVPixelBuffer>?

  public required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @MainActor
  public func input(pixelBuffer: CVPixelBuffer) {
    /**
     CALayer.contents supports displaying CVPixelBuffer implicitly.
     */
    self.layer.contents = pixelBuffer
  }

  @MainActor
  public func attach<Output: PixelBufferOutputNodeType & Sendable>(output: Output) {

    assert(Thread.isMainThread)

    subscription?.cancel()

    // Frames arrive on the delivery thread; the layer is set on main. Only the newest frame is
    // ever waiting for main — one that arrives before main has drawn the last replaces it —
    // so a busy main thread costs frames, never a queue of them.
    let pending = LatestValueSlot<CVPixelBuffer>()
    pendingFrame = pending
    subscription = output
      .pixelBufferBus
      .addHandler { [weak self, pending] pixelBuffer in
        guard pending.replace(with: pixelBuffer) else { return }
        DispatchQueue.main.async {
          guard let pixelBuffer = pending.take() else { return }
          MainActor.assumeIsolated {
            // A block queued by a subscription that has since been replaced finds a different
            // slot and draws nothing, so re-attaching never paints one last frame from the
            // previous output.
            guard let self, self.pendingFrame === pending else { return }
            self.input(pixelBuffer: pixelBuffer)
          }
        }
      }
  }

  deinit {
    subscription?.cancel()
  }

}

