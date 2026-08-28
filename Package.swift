// swift-tools-version: 6.0
// PkgLens v1.0.0
import PackageDescription

let package = Package(
    name: "PkgLens",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PkgLens", targets: ["PkgLens"])
    ],
    targets: [
        .executableTarget(
            name: "PkgLens",
            path: "Sources/PkgLens",
            resources: [
                .process("Assets.xcassets")
            ],
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=complete"])
            ]
        )
    ]
)
