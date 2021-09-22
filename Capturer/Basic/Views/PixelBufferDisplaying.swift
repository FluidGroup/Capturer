import UIKit
import AVFoundation

/**
 A protocol indicates that itself can display ``CoreVideo.CVPixelBuffer``
 */
public protocol PixelBufferDisplaying: UIView {

  func input(pixelBuffer: CVPixelBuffer)

  init()
}
