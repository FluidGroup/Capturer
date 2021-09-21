
import Foundation
import UIKit
import AVFoundation

/**
 A protocol indicates that itself can display ``CoreVideo.CVPixelBuffer``
 */
public protocol PixelBufferDisplaying: UIView {

  func input(pixelBuffer: CVPixelBuffer)

  init()
}

public final class PixelBufferView: UIView, PixelBufferDisplaying {

  public func input(pixelBuffer: CVPixelBuffer) {
    // TODO: Consider using dispatching
    DispatchQueue.main.async {
      /**
       CALayer.contents supports displaying CVPixelBuffer implicitly.
       */
      self.layer.contents = pixelBuffer
    }
  }

}


public final class CoreImagePixelBufferView: UIImageView, PixelBufferDisplaying {

  public func input(pixelBuffer: CVPixelBuffer) {
    // TODO: Consider using dispatching
    DispatchQueue.main.async {
      let image = CIImage(cvPixelBuffer: pixelBuffer, options: [:])
      self.image = UIImage.init(ciImage: image, scale: 1, orientation: .right)
    }
  }
}
