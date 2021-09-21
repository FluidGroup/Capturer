//
//  PixelBufferView.swift
//  ComponentCamera
//
//  Created by muukii on 2020/10/12.
//

import Foundation
import UIKit
import AVFoundation

public protocol PixelBufferDisplaying: UIView {

  func input(pixelBuffer: CVPixelBuffer)

  init()
}

public final class PixelBufferView: UIView, PixelBufferDisplaying {

  public func input(pixelBuffer: CVPixelBuffer) {
    DispatchQueue.main.async {
      self.layer.contents = pixelBuffer
    }
  }

}


public final class CoreImagePixelBufferView: UIImageView, PixelBufferDisplaying {

  public func input(pixelBuffer: CVPixelBuffer) {
    DispatchQueue.main.async {
      let image = CIImage(cvPixelBuffer: pixelBuffer, options: [:])
      self.image = UIImage.init(ciImage: image, scale: 1, orientation: .right)
    }
  }
}
