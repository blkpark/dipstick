// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Dipstick",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Dipstick", path: "Sources/Dipstick")
    ]
)
