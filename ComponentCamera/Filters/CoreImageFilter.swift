
import Foundation
import CoreImage

open class CoreImageFilter: CVPixelBufferModifying {

  private lazy var ciContext = MTLCreateSystemDefaultDevice()
    .map {
      CIContext(mtlDevice: $0)
    } ?? CIContext()
  private var pool: CVPixelBufferPool?

  private let filters: [CIFilter]
  private let hasFilters: Bool

  public init(filters: [CIFilter]) {
    self.filters = filters
    self.hasFilters = filters.isEmpty == false
  }

//  open func perform(upstream: CMSampleBuffer) -> CVPixelBuffer {
//
//    let pixelBuffer = CMSampleBufferGetImageBuffer(upstream)!
//    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
//    return apply(image: ciImage, original: pixelBuffer)
//  }

  open func perform(pixelBuffer upstream: CVPixelBuffer) -> CVPixelBuffer {

    let pixelBuffer = upstream
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    return apply(image: ciImage, original: upstream)
  }

  open func apply(image: CIImage, original: CVPixelBuffer) -> CVPixelBuffer {

    guard hasFilters else {
      return original
    }

    filters.first!.setValue(image, forKey: kCIInputImageKey)

    _ = filters.dropFirst().reduce(filters.first!.outputImage) { result, filter in
      filter.setValue(image, forKey: kCIInputImageKey)
      return filter.outputImage
    }

    let appliedImage = filters.last!.outputImage!

    // TODO: Consider to use another pixel-buffer instead writing into original pixel-buffer.
    ciContext.render(appliedImage, to: original, bounds: image.extent, colorSpace: image.colorSpace)

    return original
  }
}

extension CoreImageFilter {

  public static func gaussianBlur(amount: CGFloat) -> CoreImageFilter {

    let gaussianFilter = CIFilter(name: "CIGaussianBlur")!
    gaussianFilter.setValue(amount, forKey: "inputRadius")

    return .init(filters: [gaussianFilter])

  }
}
