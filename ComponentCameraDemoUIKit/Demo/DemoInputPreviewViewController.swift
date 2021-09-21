//
//  DemoInputPreviewViewController.swift
//  ComponentCameraDemoUIKit
//
//  Created by Muukii on 2021/09/21.
//

import Capturer
import Foundation
import MondrianLayout
import UIKit

@available(iOS 15, *)
final class DemoInputPreviewViewController: UIViewController {

  let sessionManager = CaptureBody()

  override func viewDidLoad() {
    super.viewDidLoad()

    let output = AnyCVPixelBufferOutput(
      upstream: VideoDataOutput()
    )

    let photoOutput = PhotoOutput()

    sessionManager.attach(output: output)
    sessionManager.attach(output: photoOutput)

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

            UIButton.make(title: "Capture") { [unowned photoOutput] in

              Task {
                do {
                  let image = try await photoOutput.capture(with: .init())
                  print(image)
                } catch {
                  print(error)
                }
              }
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
