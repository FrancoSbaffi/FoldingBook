// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FoldingBook",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "FoldingBook", targets: ["FoldingBook"])
    ],
    targets: [
        .target(name: "FoldingBookCore"),
        .executableTarget(
            name: "FoldingBook",
            dependencies: ["FoldingBookCore"]
        ),
        .executableTarget(
            name: "FoldingBookChecks",
            dependencies: ["FoldingBookCore"],
            path: "Tests/FoldingBookCoreTests"
        )
    ]
)
