//
//  AnyOutput.swift
//  ComponentCamera
//
//  Created by muukii on 2020/10/17.
//

import Foundation

public final class AnyOutput<Downstream>: OutputComponentType {

  private let backing: OutputComponentType

  public init(_ backing: OutputComponentType) {
    self.backing = backing
  }

  public func setUp(sessionInConfiguring: AVCaptureSession) {
    backing.setUp(sessionInConfiguring: sessionInConfiguring)
  }

  public func tearDown(sessionInConfiguring: AVCaptureSession) {
    backing.tearDown(sessionInConfiguring: sessionInConfiguring)
  }

}
