// swift-tools-version:6.0
import Foundation
import PackageDescription

// The Command Line Tools lose the Swift Testing macro plugin once a package has
// an executable target, so point at it directly. Xcode (and CI) finds it on its
// own. The active toolchain is DEVELOPER_DIR, else what xcode-select chose.
let cltTesting = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let developerDir = ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
    ?? (try? FileManager.default.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link")) ?? ""
// xcode-select falls back to the Command Line Tools when the chosen Xcode is gone.
let usesCommandLineTools = developerDir.hasPrefix("/Library/Developer/CommandLineTools")
    || !FileManager.default.fileExists(atPath: developerDir)
let testing: [SwiftSetting] = usesCommandLineTools && FileManager.default.fileExists(atPath: cltTesting)
    ? [.unsafeFlags(["-plugin-path", cltTesting])]
    : []

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
