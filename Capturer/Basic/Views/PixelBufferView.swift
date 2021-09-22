
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

  public func input(pixelBuffer: CVPixelBuffer) {
    // TODO: Consider using dispatching
    DispatchQueue.main.async {
      /**
       CALayer.contents supports displaying CVPixelBuffer implicitly.
       */
      self.layer.contents = pixelBuffer
    }
  }

  @MainActor
  public func attach<Output: PixelBufferOutputNodeType>(output: Output) {

    assert(Thread.isMainThread)

    subscription?.cancel()

    subscription = output
      .pixelBufferBus
      .addHandler { [unowned self] pixelBuffer in
        self.input(pixelBuffer: pixelBuffer)
    }
  }

  deinit {
    subscription?.cancel()
  }

}

