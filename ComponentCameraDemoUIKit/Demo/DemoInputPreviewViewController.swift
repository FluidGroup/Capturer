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

  override func viewDidLoad() {
    super.viewDidLoad()

    view.backgroundColor = .white

    // Set Up

    let input = CameraInput.wideAngleCamera(position: .back)
    captureBody.attach(input: input)

    let previewOutput = VideoDataOutput()
    let photoOutput = PhotoOutput()

    captureBody.attach(output: previewOutput)
    captureBody.attach(output: photoOutput)

    let previewView = PixelBufferView()
    previewView.attach(output: previewOutput)

    captureBody.start()

    OrientationManager.shared.start()

    // Layout

    view.mondrian.buildSubviews {
      LayoutContainer(attachedSafeAreaEdges: .all) {
        VStackBlock(alignment: .fill) {
          previewView

          HStackBlock(spacing: 4) {

            UIButton.make(title: "Use back") { [unowned self] in
              let input = CameraInput.wideAngleCamera(position: .back)
              captureBody.attach(input: input)
            }

            UIButton.make(title: "Use front") { [unowned self] in
              let input = CameraInput.wideAngleCamera(position: .front)
              captureBody.attach(input: input)
            }

            UIButton.make(title: "Remove input") { [unowned self] in
              captureBody.removeCurrentInput()
            }

            UIButton.make(title: "Capture") { [unowned photoOutput] in

              Task {
                do {
                  let image = try await photoOutput.capture(with: .init())
                  let cgImage = image.cgImageRepresentation()!
                  UIImageWriteToSavedPhotosAlbum(UIImage(cgImage: cgImage), nil, nil, nil)
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

}
