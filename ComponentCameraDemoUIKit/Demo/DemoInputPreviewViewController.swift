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

@available(iOS 14, *)
final class DemoInputPreviewViewController: UIViewController {

  let sessionManager = CaptureBody()

  override func viewDidLoad() {
    super.viewDidLoad()

    let output = AnyCVPixelBufferOutput(upstream: VideoDataOutput(), filter: CoreImageFilter())

    sessionManager.attach(output: output)

    let previewView = PixelBufferView()

    let setInputButton = UIButton(type: .system, primaryAction: .init { [unowned self] _ in

      let input = CameraInput()

      sessionManager.attach(input: input)
    })

    setInputButton.setTitle("Set input", for: .normal)

    view.mondrian.buildSubviews {
      LayoutContainer(attachedSafeAreaEdges: .all) {
        VStackBlock(alignment: .fill) {
          previewView

          HStackBlock {
            setInputButton
          }
        }
      }
    }

    output.sampleBufferBus.addHandler { pixelBuffer in
      previewView.input(pixelBuffer: pixelBuffer)
    }

  }

}
