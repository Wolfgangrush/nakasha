// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NAKASHA",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "NAKASHA", targets: ["NakashaApp"]),
        // The CLI product name must never differ from the app's only by case. macOS
        // filesystems are case-insensitive by default, so "NAKASHA" and "nakasha" would
        // resolve to the same path in .build and the app would silently overwrite the CLI
        // binary — running the "CLI" then launches a GUI event loop and appears to hang.
        .executable(name: "nakasha-cli", targets: ["NakashaCLI"]),
        .library(name: "NakashaCore", targets: ["NakashaCore"]),
    ],
    dependencies: [],   // zero third-party dependencies, permanently — 01-PRD §4
    targets: [
        // Pure, UI-free, network-free parsing + rendering. Everything testable lives here.
        .target(name: "NakashaCore", path: "Sources/NakashaCore"),
        // SwiftUI front door — the thing an advocate double-clicks.
        .executableTarget(
            name: "NakashaApp",
            dependencies: ["NakashaCore"],
            path: "Sources/NakashaApp"
        ),
        // Headless CLI — same core, for scripting and for calibrating a new court format.
        .executableTarget(
            name: "NakashaCLI",
            dependencies: ["NakashaCore"],
            path: "Sources/NakashaCLI"
        ),
        .testTarget(
            name: "NakashaCoreTests",
            dependencies: ["NakashaCore"],
            path: "Tests/NakashaCoreTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
