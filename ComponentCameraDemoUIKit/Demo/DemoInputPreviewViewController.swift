//
//  DemoInputPreviewViewController.swift
//  ComponentCameraDemoUIKit
//
//  Created by Muukii on 2021/09/21.
//

import ComponentCamera
import Foundation
import MondrianLayout
import UIKit

@available(iOS 14, *)
final class DemoInputPreviewViewController: UIViewController {

  let sessionManager = CaptureBody()

  override func viewDidLoad() {
    super.viewDidLoad()

    let output = AnyCVPixelBufferOutput(
      upstream: VideoDataOutput(),
      filter: CoreImageFilter.gaussianBlur(amount: 60)
    )

    sessionManager.attach(output: output)

    let previewView = PixelBufferView()

    sessionManager.start()

    view.mondrian.buildSubviews {
      LayoutContainer(attachedSafeAreaEdges: .all) {
        VStackBlock(alignment: .fill) {
          previewView

          HStackBlock {

            UIButton.make(title: "Set input") { [unowned self] in
              let input = CameraInput()
              sessionManager.attach(input: input)
            }

          }
        }
      }
    }

    output.sampleBufferBus.addHandler { pixelBuffer in
      previewView.input(pixelBuffer: pixelBuffer)
    }

  }

}
