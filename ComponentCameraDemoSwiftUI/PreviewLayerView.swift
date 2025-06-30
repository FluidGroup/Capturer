//
//  PreviewLayerView.swift
//  ComponentCameraDemoSwiftUI
//
//  Created by muukii on 2020/10/12.
//

import Foundation
import SwiftUI
import AVFoundation
import Capturer

final class _CaptureVideoPreviewView: UIView {

  class Layer: AVCaptureVideoPreviewLayer {
    override var contents: Any? {
      didSet {
        print(contents)
      }
    }
  }

  override class var layerClass: AnyClass {
    return Layer.self
  }

  /// Convenience wrapper to get layer as its statically known type.
  var videoPreviewLayer: AVCaptureVideoPreviewLayer {
    return layer as! Layer
  }

}

struct CaptureVideoPreview: UIViewRepresentable {

  let session: AVCaptureSession

  init(session: AVCaptureSession) {
    self.session = session
  }

  func makeUIView(context: Context) -> _CaptureVideoPreviewView {
    let view = _CaptureVideoPreviewView()
    view.videoPreviewLayer.session = session
    return view
  }

  func updateUIView(_ uiView: _CaptureVideoPreviewView, context: Context) {

  }

  typealias UIViewType = _CaptureVideoPreviewView

}

struct CustomPixelBufferView<View: PixelBufferDisplaying>: UIViewRepresentable {

  typealias Output = AnyCVPixelBufferOutput

  final class Coordinator {
    let output: Output
    var cancellable: EventBusCancellable?

    init(output: Output) {
      self.output = output
    }
  }

  let output: Output

  init(output: Output) {
    self.output = output
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(output: output)
  }

  func makeUIView(context: Context) -> View {
    let view = View()

    Task {
      let cancellable = await context.coordinator.output.pixelBufferBus.addHandler { [weak view] (buffer) in
        guard let view = view else { return }
        Task {
          await view.input(pixelBuffer: buffer)
        }
      }
      context.coordinator.cancellable = cancellable
    }


    return view
  }

  func updateUIView(_ uiView: View, context: Context) {

  }

  static func dismantleUIView(_ uiView: View, coordinator: Coordinator) {
    coordinator.cancellable?.cancel()
  }

}
