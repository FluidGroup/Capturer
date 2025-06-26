//
//  ContentView.swift
//  ComponentCameraDemoSwiftUI
//
//  Created by muukii on 2020/10/12.
//

import Capturer
import SwiftUI

extension CoreImageFilter: @retroactive @unchecked Sendable {}

@MainActor
final class ViewModel: ObservableObject {

  let sessionManager = CaptureBody(
    configuration: .init {
      $0.sessionPreset = .photo
    }
  )
  let output: AnyCVPixelBufferOutput

  init() {

    let output = AnyCVPixelBufferOutput(
      upstream: PreviewOutput(),
      filter: CoreImageFilter(filters: [])
    )
    self.output = output

    Task {

      let input = try CameraInput.bestBuiltInDevice(position: .back)
     sessionManager.attach(input: input)
     sessionManager.attach(output: output)
     sessionManager.start()
    }

  }

}

struct ContentView: View {
  var body: some View {
    VStack {
      CameraView()
    }
  }
}

struct CameraView: View {

  @StateObject var viewModel: ViewModel = .init()

  var body: some View {

    //    CustomPixelBufferView<CoreImagePixelBufferView>(body: viewModel.sessionManager)
    CustomPixelBufferView<PixelBufferView>(output: viewModel.output)
    //
    //    CustomPixelBufferView<CoreImagePixelBufferView>(body: viewModel.sessionManager)
    //    CustomPixelBufferView<PixelBufferView>(body: viewModel.sessionManager)

  }

}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    ContentView()
  }
}
