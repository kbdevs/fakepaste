// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FakePaste",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "FakePasteApp", targets: ["FakePasteApp"]),
        .library(name: "FakePasteCore", targets: ["FakePasteCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/kbdevs/SwiftPermiso", branch: "main"),
    ],
    targets: [
        .target(name: "FakePasteCore"),
        .executableTarget(
            name: "FakePasteApp",
            dependencies: ["FakePasteCore", "SwiftPermiso"]
        ),
        .testTarget(
            name: "FakePasteCoreTests",
            dependencies: ["FakePasteCore"]
        ),
    ]
)
