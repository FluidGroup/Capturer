// swift-tools-version:5.5
import PackageDescription

let package = Package(
  name: "Capturer",
  platforms: [.iOS(.v13)],
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
