//
//  DemoInputPreviewClassicViewController.swift
//  CapturerDemoUIKit
//
//  Created by Muukii on 2021/10/14.
//

import Capturer
import MondrianLayout
import UIKit

@available(iOS 14, *)
final class DemoInputPreviewClassicViewController: UIViewController {

  private let captureBody = CaptureBody(
    configuration: .init {
      $0.sessionPreset = .photo
    }
  )

  var isMirrored = false

  override func viewDidLoad() {
    super.viewDidLoad()

    view.backgroundColor = .white

    // Set Up

    let input = CameraInput.wideAngleCamera(position: .back)

    let previewOutput = PreviewOutput()
    let photoOutput = PhotoOutput()

    let previewView = PixelBufferView()
    previewView.attach(output: previewOutput)

    Task {

      await captureBody.batchAttaching(
        input: input,
        outputs: [
          previewOutput,
          photoOutput,
        ]
      )
      let ratio = previewOutput.state.inputInfo!.aspectRatioRespectingVideoOrientation

      view.mondrian.buildSubviews {
        LayoutContainer(attachedSafeAreaEdges: .all) {
          VStackBlock(alignment: .fill) {
            previewView
              .viewBlock
              .aspectRatio(ratio)
          }
        }
      }
      await captureBody.start()
    }

  }

  // Layout

}
