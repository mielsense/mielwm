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
    // Test only: Barik's TOML decoder, at the version Barik pins, to read the configs mielwm edits as Barik does.
    dependencies: [.package(url: "https://github.com/dduan/TOMLDecoder", exact: "0.3.1")],
    targets: [
        // Pure logic and the shared types every other target codes against.
        .target(name: "MielCore"),
        // Metal renderer. Shaders are compiled at runtime from source strings:
        // the Command Line Tools have no `metal` compiler.
        .target(name: "MielRender", dependencies: ["MielCore"],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        // The socket `mielwm <action>` and the `aerospace` command talk over. Foundation only.
        .target(name: "MielIPC", swiftSettings: [.swiftLanguageMode(.v5)]),
        // Accessibility, event tap, ScreenCaptureKit, displays.
        .target(name: "MielSystem", dependencies: ["MielCore"],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "mielwm",
                          dependencies: ["MielCore", "MielIPC", "MielRender", "MielSystem"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        // Barik's `aerospace` command and the hidden AeroSpace helper app, one small binary
        // (docs/aerospace.md). Barik runs it up to 40 times a second, so it links no Foundation.
        // `os` and `Dispatch` autolink Combine, which loads Foundation: drop what goes unused.
        .executableTarget(name: "mielwm-aerospace", path: "Sources/MielAeroSpace",
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-dead_strip_dylibs"])]),
        // Throwaway windows for system tests, so tests never move real ones.
        .executableTarget(name: "mielwm-testwindows", path: "Sources/MielTestWindows",
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "MielCoreTests", dependencies: ["MielCore", .product(name: "TOMLDecoder", package: "TOMLDecoder")],
                    swiftSettings: testing),
        .testTarget(name: "MielRenderTests", dependencies: ["MielRender", "MielCore"], swiftSettings: testing),
        // The app's own logic, from the executable module; nothing here opens windows.
        .testTarget(name: "mielwmTests", dependencies: ["mielwm", "MielCore", "MielSystem"], swiftSettings: testing),
        .testTarget(name: "MielSystemTests", dependencies: ["MielSystem", "MielIPC", "MielCore"],
                    exclude: ["Fixtures"], swiftSettings: testing),
    ]
)
