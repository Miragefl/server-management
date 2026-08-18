// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ServerManagement",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ServerManagement",
            path: "Sources/ServerManagement"
        ),
        .testTarget(
            name: "ServerManagementTests",
            dependencies: ["ServerManagement"],
            path: "Tests/ServerManagementTests"
        ),
    ]
)
