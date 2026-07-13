// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AIOS",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0")
    ],
    targets: [
        .target(name: "AIOSCore"),
        .executableTarget(
            name: "AIOS",
            dependencies: [
                "AIOSCore",
                .product(name: "WhisperKit", package: "WhisperKit")
            ]
        ),
        .testTarget(name: "AIOSCoreTests", dependencies: ["AIOSCore"])
    ]
)
