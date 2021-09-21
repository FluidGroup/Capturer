//
//  PixelBufferTransform.swift
//  ComponentCamera
//
//  Created by muukii on 2020/10/17.
//

import Foundation
import CoreImage

open class CoreImagePixelBufferTransform: MapOutput<CMSampleBuffer, CVPixelBuffer> {

  private let ciContext = CIContext() // TODO: Use Metal

  private let upstream: AnyCMSampleBufferOutput
  private let pool: CVPixelBufferPool

  public init(_ upstream: AnyCMSampleBufferOutput) {
    self.upstream = upstream

    var _pool: CVPixelBufferPool?

    CVPixelBufferPoolCreate(nil, nil, nil, &_pool)
    self.pool = _pool!
  }

  open override func perform(upstream: CMSampleBuffer) -> CVPixelBuffer {

    let pixelBuffer = CMSampleBufferGetImageBuffer(upstream)!
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    return apply(image: ciImage)
  }

  open func apply(image: CIImage) -> CVPixelBuffer {

    var pixelBuffer: CVPixelBuffer!

    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)

    ciContext.render(image, to: pixelBuffer, bounds: image.extent, colorSpace: image.colorSpace)

    return pixelBuffer
  }

}
