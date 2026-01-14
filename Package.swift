// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ink",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ink", targets: ["ink"])
    ],
    dependencies: [
        .package(url: "https://github.com/johnxnguyen/Down.git", from: "0.11.0")
    ],
    targets: [
        .executableTarget(
            name: "ink",
            dependencies: ["Down"],
            path: "Sources/ink",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
