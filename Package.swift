// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Atten",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AttenCore", targets: ["AttenCore"]),
        .executable(name: "Atten", targets: ["Atten"]),
        .executable(name: "AttenFixtures", targets: ["AttenFixtures"]),
    ],
    targets: [
        .target(name: "AttenCore"),
        .executableTarget(
            name: "Atten",
            dependencies: ["AttenCore"],
            exclude: ["Resources"]
        ),
        /// The document and audio builders behind the #90 stress fixtures and
        /// the `make-fixture-library` QA tool, kept XCTest-free so both an
        /// executable and the test target can link it.
        .target(
            name: "AttenFixtureKit",
            dependencies: ["AttenCore"]
        ),
        .executableTarget(
            name: "AttenFixtures",
            dependencies: ["AttenCore", "AttenFixtureKit"]
        ),
        .testTarget(
            name: "AttenCoreTests",
            dependencies: ["AttenCore", "Atten", "AttenFixtureKit"],
            path: "tests/AttenCoreTests"
        ),
    ]
)
