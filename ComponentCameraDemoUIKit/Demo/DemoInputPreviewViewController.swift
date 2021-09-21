//
//  DemoInputPreviewViewController.swift
//  ComponentCameraDemoUIKit
//
//  Created by Muukii on 2021/09/21.
//

import Foundation
import ComponentCamera
import MondrianLayout
import UIKit

final class DemoInputPreviewViewController: UIViewController {

  let sessionManager = CameraBody()

  override func viewDidLoad() {
    super.viewDidLoad()

    let output = AnyCVPixelBufferOutput(upstream: VideoDataOutput(), filter: CoreImageFilter())

    sessionManager.attach(output: output)

    let previewView = PixelBufferView()

    view.mondrian.buildSubviews {
      LayoutContainer(attachedSafeAreaEdges: .all) {
        VStackBlock(alignment: .fill) {
          previewView
        }
      }
    }

    output.sampleBufferBus.addHandler { pixelBuffer in
      previewView.input(pixelBuffer: pixelBuffer)
    }

  }

}
