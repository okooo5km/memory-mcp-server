// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "memory-mcp-server",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/gsabran/mcp-swift-sdk", from: "0.2.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "memory-mcp-server",
            dependencies: [
                .product(name: "MCPServer", package: "mcp-swift-sdk")
            ]
        )
    ]
)
