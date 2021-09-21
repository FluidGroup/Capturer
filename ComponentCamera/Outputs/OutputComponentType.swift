//
//  OutputComponentType.swift
//  ComponentCamera
//
//  Created by muukii on 2020/10/12.
//

import Foundation
import AVFoundation

public protocol OutputComponentType: AnyObject {
  func setUp(sessionInConfiguring: AVCaptureSession)
  func tearDown(sessionInConfiguring: AVCaptureSession)
}
