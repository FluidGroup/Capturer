//
//  InputComponentType.swift
//  ComponentCamera
//
//  Created by muukii on 2020/10/12.
//

import Foundation
import AVFoundation

public protocol InputComponentType: AnyObject {
  func setUp(sessionInConfiguring: AVCaptureSession)
  func tearDown(sessionInConfiguring: AVCaptureSession)
}
