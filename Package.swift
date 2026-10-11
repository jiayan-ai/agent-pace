// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentPace",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "AgentPace", targets: ["AgentPace"])],
    targets: [
        .target(name: "PaceCore"),
        .executableTarget(name: "AgentPace", dependencies: ["PaceCore"]),
        .executableTarget(name: "PaceCoreChecks", dependencies: ["PaceCore"], path: "Tests/PaceCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
