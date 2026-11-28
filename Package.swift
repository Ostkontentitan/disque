// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Disque",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Disque", targets: ["Disque"])
    ],
    targets: [
        .executableTarget(
            name: "Disque",
            path: "Sources/Disque"
        ),
        .testTarget(
            name: "DisqueTests",
            dependencies: ["Disque"],
            path: "Tests/DisqueTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
