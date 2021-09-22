import UIKit
import AVFoundation

public final class CoreImagePixelBufferView: UIImageView, PixelBufferDisplaying {

  public func input(pixelBuffer: CVPixelBuffer) {
    // TODO: Consider using dispatching
    DispatchQueue.main.async {
      let image = CIImage(cvPixelBuffer: pixelBuffer, options: [:])
      self.image = UIImage.init(ciImage: image, scale: 1, orientation: .right)
    }
  }
}
