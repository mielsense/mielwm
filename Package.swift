// swift-tools-version:6.0
import PackageDescription

// shortcut: with an executable target in the package, Command Line Tools'
// SwiftPM loses the Swift Testing macro plugin; point at it directly. Drop
// this once `swift test` works without it.
let testing: [SwiftSetting] = [.unsafeFlags([
    "-plugin-path", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing",
])]

let package = Package(
    name: "mielwm",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "mielwm", targets: ["mielwm"])],
    targets: [
        // Pure logic and the shared types every other target codes against.
        .target(name: "MielCore"),
        // Metal renderer. Shaders are compiled at runtime from source strings:
        // the Command Line Tools have no `metal` compiler.
        .target(name: "MielRender", dependencies: ["MielCore"],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        // Accessibility, event tap, ScreenCaptureKit, displays.
        .target(name: "MielSystem", dependencies: ["MielCore"],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "mielwm",
                          dependencies: ["MielCore", "MielRender", "MielSystem"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        // Throwaway windows for system tests, so tests never move real ones.
        .executableTarget(name: "mielwm-testwindows", path: "Sources/MielTestWindows",
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "MielCoreTests", dependencies: ["MielCore"], swiftSettings: testing),
        .testTarget(name: "MielRenderTests", dependencies: ["MielRender", "MielCore"], swiftSettings: testing),
        .testTarget(name: "MielSystemTests", dependencies: ["MielSystem", "MielCore"],
                    exclude: ["Fixtures"], swiftSettings: testing),
    ]
)
