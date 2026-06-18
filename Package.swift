// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Atten",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AttenCore", targets: ["AttenCore"]),
        .executable(name: "Atten", targets: ["Atten"]),
    ],
    targets: [
        .target(name: "AttenCore"),
        .executableTarget(
            name: "Atten",
            dependencies: ["AttenCore"],
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "AttenCoreTests",
            dependencies: ["AttenCore", "Atten"],
            path: "tests/AttenCoreTests"
        ),
    ]
)
