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

    Task {

      do {

        let indicator = UIActivityIndicatorView(style: .large)

        view.mondrian.buildSubviews {
          ZStackBlock {
            indicator
          }
        }

        indicator.startAnimating()
      }

      let input = CameraInput.wideAngleCamera(position: .back)
      await captureBody.attach(input: input)

      let previewOutput = PreviewOutput()
      let photoOutput = PhotoOutput()

      await captureBody.attach(output: previewOutput)
      await captureBody.attach(output: photoOutput)

      let previewView = PixelBufferView()
      previewView.attach(output: previewOutput)

      captureBody.start()

      let ratio = previewOutput.state.inputInfo!.aspectRatioRespectingVideoOrientation

      view.subviews.forEach {
        $0.removeFromSuperview()
      }

      view.mondrian.buildSubviews {
        LayoutContainer(attachedSafeAreaEdges: .all) {
          VStackBlock(alignment: .fill) {
            previewView
              .viewBlock
              .aspectRatio(ratio)

            HStackBlock(spacing: 4) {

              UIButton.make(title: "Use back") { [unowned self] in
                Task { [weak self] in
                  let input = CameraInput.wideAngleCamera(position: .back)
                  await captureBody.attach(input: input)
                  previewOutput.setIsMirroringEnabled(false)
                  self?.isMirrored = false
                }
              }

              UIButton.make(title: "Use front") { [unowned self] in
                Task { [weak self] in
                  let input = CameraInput.wideAngleCamera(position: .front)
                  await captureBody.attach(input: input)
                  previewOutput.setIsMirroringEnabled(true)
                  self?.isMirrored = true
                }
              }

              UIButton.make(title: "Remove input") { [unowned self] in
                captureBody.removeCurrentInput()
              }

              UIButton.make(title: "Capture") { [unowned photoOutput, unowned self] in

                Task { [weak self] in
                  do {

                    let result = try await photoOutput.capture(with: photoOutput.makeCaptureSettings())

                    guard let self = self else { return }

                    let image = result.makeOrientationFixedImage(isMirrored: self.isMirrored)
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    print(image)
                  } catch {
                    print(error)
                  }
                }
              }

              StackingSpacer(minLength: 0)

            }
          }
        }
      }
    }

    // Layout

  }

}
