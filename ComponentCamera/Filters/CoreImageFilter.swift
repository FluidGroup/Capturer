//
//  CoreImageFilter.swift
//  ComponentCamera
//
//  Created by muukii on 2020/10/17.
//

import Foundation
import CoreImage

open class CoreImageFilter {

  private let ciContext = CIContext() // TODO: Use Metal
  private var pool: CVPixelBufferPool?

  public init() {

  }

  private func createPool(sample pixelBuffer: CVPixelBuffer) {
    guard pool == nil else { return }

//    CVPixelget
//
//    var _pool: CVPixelBufferPool?
//    CVPixelBufferPoolCreate(
//      kCFAllocatorDefault,
//      nil,
//      [
//        kCVPixelBufferPixelFormatTypeKey : k32BGRAPixelFormat,
//        kCVPixelBufferWidthKey : 0,
//
//      ] as CFDictionary,
//      &_pool
//    )
//    self.pool = _pool!

  }

  open func perform(upstream: CMSampleBuffer) -> CVPixelBuffer {

    let pixelBuffer = CMSampleBufferGetImageBuffer(upstream)!
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    return apply(image: ciImage, original: pixelBuffer)
  }

  open func perform(upstream: CVPixelBuffer) -> CVPixelBuffer {

    let pixelBuffer = upstream
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    return apply(image: ciImage, original: upstream)
  }

  open func apply(image: CIImage, original: CVPixelBuffer) -> CVPixelBuffer {

    let appliedImage = image.applyingGaussianBlur(sigma: 60)
    ciContext.render(appliedImage, to: original, bounds: image.extent, colorSpace: image.colorSpace)

    return original
  }
}
