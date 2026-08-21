// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "MXMasterControl",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "MXMasterCore", targets: ["MXMasterCore"]),
    .library(name: "MXMasterHID", targets: ["MXMasterHID"]),
    .library(name: "MXMasterLifecycle", targets: ["MXMasterLifecycle"]),
    .library(name: "MXMasterActions", targets: ["MXMasterActions"]),
    .executable(name: "MXMasterControl", targets: ["MXMasterControl"]),
    .executable(name: "mxmasterctl", targets: ["mxmasterctl"]),
  ],
  targets: [
    .target(name: "MXMasterCore"),
    .target(
      name: "MXMasterHID",
      dependencies: ["MXMasterCore"],
      linkerSettings: [.linkedFramework("IOKit")]
    ),
    .target(
      name: "MXMasterLifecycle",
      dependencies: ["MXMasterHID"]
    ),
    .target(
      name: "MXMasterActions",
      dependencies: ["MXMasterCore"],
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("ApplicationServices"),
      ]
    ),
    .executableTarget(
      name: "mxmasterctl",
      dependencies: ["MXMasterCore", "MXMasterHID"]
    ),
    .executableTarget(
      name: "MXMasterControl",
      dependencies: ["MXMasterActions", "MXMasterCore", "MXMasterHID", "MXMasterLifecycle"],
      path: "Sources/MXMasterControlApp",
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("ServiceManagement"),
      ]
    ),
    .testTarget(
      name: "MXMasterCoreTests",
      dependencies: ["MXMasterCore"]
    ),
    .testTarget(
      name: "MXMasterHIDTests",
      dependencies: ["MXMasterCore", "MXMasterHID"]
    ),
    .testTarget(
      name: "MXMasterLifecycleTests",
      dependencies: ["MXMasterLifecycle"]
    ),
    .testTarget(
      name: "MXMasterActionsTests",
      dependencies: ["MXMasterActions", "MXMasterCore"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
