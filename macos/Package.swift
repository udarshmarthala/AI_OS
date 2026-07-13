// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AIOS",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "6.3.2")
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
        .testTarget(
            name: "AIOSCoreTests",
            dependencies: [
                "AIOSCore",
                .product(name: "Testing", package: "swift-testing")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
                ])
            ]
        )
    ]
)
