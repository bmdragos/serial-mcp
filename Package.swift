// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "serial-mcp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "serial-mcp", targets: ["serial-mcp"])
    ],
    targets: [
        .executableTarget(
            name: "serial-mcp",
            path: "Sources"
        )
    ]
)
