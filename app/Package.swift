// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PetOS",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PetOS",
            path: "Sources/PetOS",
            resources: [.process("Resources")]
        )
    ],
    swiftLanguageVersions: [.v5]
)
