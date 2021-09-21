//
//  MapOutput.swift
//  ComponentCamera
//
//  Created by muukii on 2020/10/17.
//

import Foundation

open class MapOutput<Upstream, Downstream>: OutputComponentType {

  open func perform(upstream: Upstream) -> Downstream {
    fatalError("Must be override")
  }

  public func setUp(sessionInConfiguring: AVCaptureSession) {

  }

  public func tearDown(sessionInConfiguring: AVCaptureSession) {

  }
}
