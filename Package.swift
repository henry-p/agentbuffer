// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentBuffer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AgentBuffer", targets: ["AgentBuffer"])
    ],
    dependencies: [
        .package(path: "Vendor/OpenPanel")
    ],
    targets: [
        .executableTarget(
            name: "AgentBuffer",
            dependencies: [
                .product(name: "OpenPanel", package: "OpenPanel")
            ],
            path: "Sources/AgentBuffer",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
