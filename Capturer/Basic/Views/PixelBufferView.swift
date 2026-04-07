
import Foundation
import UIKit
import AVFoundation

public final class PixelBufferView: UIView, PixelBufferDisplaying {

  public override init(frame: CGRect) {
    super.init(frame: frame)

    layer.contentsGravity = .resizeAspect
  }

  private var subscription: EventBusCancellable?

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

    Task { [weak self] in
      let subscription = await output
        .pixelBufferBus
        .addHandler { [weak self] pixelBuffer in
          Task { @MainActor in
            self?.input(pixelBuffer: pixelBuffer)
          }
        }
      self?.subscription = subscription
    }
  }

  deinit {
    subscription?.cancel()
  }

}

