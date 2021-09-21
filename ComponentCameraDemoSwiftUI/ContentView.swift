//
//  ContentView.swift
//  ComponentCameraDemoSwiftUI
//
//  Created by muukii on 2020/10/12.
//

import SwiftUI
import Capturer

class ViewModel: ObservableObject {

  let sessionManager = CaptureBody()
  let output: AnyCVPixelBufferOutput

  init() {

    let output = AnyCVPixelBufferOutput(upstream: VideoDataOutput(), filter: CoreImageFilter())
    self.output = output

    sessionManager.attach(output: output)
    sessionManager.start()

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
