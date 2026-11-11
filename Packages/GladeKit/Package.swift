// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "GladeKit",
  platforms: [.macOS(.v26)],
  products: [
    .library(name: "GladeKit", targets: ["GladeKit"]),
    .library(name: "GladeCLI", targets: ["GladeCLI"]),
    .library(name: "GladeUI", targets: ["GladeUI"]),
    .executable(name: "glade", targets: ["glade"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
  ],
  targets: [
    // The engine: metrics, scanning, safety policy, cleaning, agents. No UI.
    .target(name: "GladeKit"),
    // The command layer. The app's own executable runs this when invoked with a
    // subcommand, and the `glade` executable below runs it during development.
    .target(
      name: "GladeCLI",
      dependencies: [
        "GladeKit",
        "GladeUI",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
    // The interface. It lives in the package so it builds and renders without Xcode.
    .target(
      name: "GladeUI",
      dependencies: ["GladeKit"],
      swiftSettings: [.defaultIsolation(MainActor.self)]
    ),
    .executableTarget(name: "glade", dependencies: ["GladeCLI"]),
    .testTarget(name: "GladeKitTests", dependencies: ["GladeKit"]),
  ],
  swiftLanguageModes: [.v6]
)
