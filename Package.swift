// swift-tools-version:6.0.0
import PackageDescription

let package = Package(
  name: "Capturer",
  platforms: [.iOS(.v16)],
  products: [
    .library(name: "Capturer", targets: ["Capturer"]),
  ],
  dependencies: [
  ],
  targets: [
    .target(
      name: "Capturer",
      dependencies: [],
      path: "Capturer"
    ),
  ]
)
