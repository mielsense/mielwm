import Foundation
import MielCore
@testable import MielSystem
import Testing

// BarikLink on scratch homes, with stand-ins for Barik and the helper: no real app is touched.

@MainActor
private final class FakeApps: BarikApps {
    var barik: Date? // when the running Barik started
    var helperStart = Date(timeIntervalSince1970: 1000)
    var relaunched = 0
    var helperRunning = false

    func barikLaunched() -> Date? { barik }
    func relaunchBarik() { if barik != nil { relaunched += 1 } }
    func startHelper(_ url: URL, started: @escaping (Date?) -> Void) {
        helperRunning = true
        started(helperStart)
    }

    func stopHelper() { helperRunning = false }
}

private let shim = "/Applications/mielwm.app/Contents/Helpers/aerospace"
private let original = "theme = \"system\"\n\n[widgets]\ndisplayed = [\"default.spaces\"]\n"

/// Defaults kept in memory: nothing lands in ~/Library/Preferences, and runs in other checkouts can't touch them.
private final class MemoryDefaults: UserDefaults {
    private var values: [String: Any] = [:]
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func object(forKey key: String) -> Any? { values[key] }
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func removeObject(forKey key: String) { values[key] = nil }
}

@MainActor
private func link(_ apps: FakeApps, shim: String = shim) throws -> (BarikLink, home: URL) {
    let home = try scratchDir("barik")
    let defaults = try #require(MemoryDefaults(suiteName: nil))
    return (BarikLink(home: home, shim: shim, helper: URL(fileURLWithPath: "/x/AeroSpace.app"), apps: apps, defaults: defaults), home)
}

private func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

/// Apps that run the aerospace command need no config of Barik's: the helper starts, and no file is written.
@MainActor @Test func withoutAConfigOnlyTheHelperStarts() throws {
    let apps = FakeApps()
    let (barik, home) = try link(apps)
    #expect(barik.config == nil)
    try barik.turnOn()
    #expect(try FileManager.default.contentsOfDirectory(atPath: home.path).isEmpty)
    #expect(apps.helperRunning && apps.relaunched == 0)
    try barik.turnOff()
    #expect(!apps.helperRunning)
    #expect(try FileManager.default.contentsOfDirectory(atPath: home.path).isEmpty)
}

@MainActor @Test func onEditsWithABackupStartsTheHelperAndRelaunchesBarik() throws {
    let apps = FakeApps()
    apps.barik = .distantPast
    let (barik, home) = try link(apps)
    let file = home.appendingPathComponent(".config/barik/config.toml")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try original.write(to: file, atomically: false, encoding: .utf8)
    #expect(barik.config == file)

    try barik.turnOn()
    #expect(try read(file).contains("aerospace.path = \"\(shim)\""))
    let backup = URL(fileURLWithPath: file.path + ".mielwm-backup")
    #expect(try read(backup) == original)
    #expect(apps.helperRunning && apps.relaunched == 1)

    // A second edit never replaces the first backup.
    try (try read(file)).replacingOccurrences(of: "system", with: "dark").write(to: file, atomically: false, encoding: .utf8)
    try barik.turnOff()
    try barik.turnOn()
    #expect(try read(backup) == original)

    try barik.turnOff()
    #expect(try read(file) == original.replacingOccurrences(of: "system", with: "dark"))
    #expect(!apps.helperRunning && apps.relaunched == 4)
}

@MainActor @Test func offPutsBackThePathBarikHadBefore() throws {
    let apps = FakeApps()
    let (barik, home) = try link(apps)
    let file = home.appendingPathComponent(".barik-config.toml")
    let before = withBrew
    try before.write(to: file, atomically: false, encoding: .utf8)
    try barik.turnOn()
    #expect(try read(file).contains("aerospace.path = \"\(shim)\""))
    #expect(apps.relaunched == 0) // Barik isn't running
    try barik.turnOff()
    #expect(try read(file) == before)
}

@MainActor @Test func aSymlinkedConfigStaysALink() throws {
    let apps = FakeApps()
    let (barik, home) = try link(apps)
    let target = home.appendingPathComponent("dotfiles/barik.toml")
    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try original.write(to: target, atomically: false, encoding: .utf8)
    let file = home.appendingPathComponent(".barik-config.toml")
    try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)

    try barik.turnOn()
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: file.path) == target.path)
    #expect(try read(target).contains("aerospace.path = \"\(shim)\""))
    try barik.turnOff()
    #expect(try read(target) == original)
}

@MainActor @Test func atLaunchBarikIsRelaunchedOnlyIfItStartedBeforeTheHelper() throws {
    let apps = FakeApps()
    let (barik, _) = try link(apps)
    barik.resume()
    #expect(apps.helperRunning && apps.relaunched == 0) // no Barik

    apps.barik = apps.helperStart.addingTimeInterval(2)
    barik.resume()
    #expect(apps.relaunched == 0) // it saw the helper

    apps.barik = apps.helperStart.addingTimeInterval(-60)
    barik.resume()
    #expect(apps.relaunched == 1)
}

// The same user and settings, another copy of mielwm.app: moved between
// /Applications and ~/Applications, or run from Downloads or the disk image.
private let shimB = "/Users/u/Applications/mielwm.app/Contents/Helpers/aerospace"
private let brew = "'/opt/homebrew/bin/aerospace'"
private let withBrew = "aerospace.path = \(brew)\n" + original

@MainActor
private func moved(_ barik: BarikLink, to shim: String) -> BarikLink {
    BarikLink(home: barik.home, shim: shim, helper: barik.helper, apps: barik.apps, defaults: barik.defaults)
}

@MainActor
private func barikConfig(_ text: String, in home: URL) throws -> URL {
    let file = home.appendingPathComponent(".barik-config.toml")
    try text.write(to: file, atomically: false, encoding: .utf8)
    return file
}

@MainActor @Test func offFromAnotherCopyGivesBackTheFileAsItWas() throws {
    for before in [original, withBrew] {
        let (a, home) = try link(FakeApps())
        let file = try barikConfig(before, in: home)
        try a.turnOn()
        try moved(a, to: shimB).turnOff()
        #expect(try read(file) == before)
        #expect(a.defaults.string(forKey: BarikLink.previousKey) == nil)
    }
}

@MainActor @Test func onFromAnotherCopyKeepsTheUsersPath() throws {
    let before = withBrew
    let (a, home) = try link(FakeApps())
    let file = try barikConfig(before, in: home)
    try a.turnOn()
    let b = moved(a, to: shimB)
    try b.turnOn()
    #expect(try read(file).contains("aerospace.path = \"\(shimB)\""))
    #expect(a.defaults.string(forKey: BarikLink.previousKey) == brew)
    try b.turnOff()
    #expect(try read(file) == before)
}

@MainActor @Test func atLaunchAnotherCopyPointsBarikAtItself() throws {
    let apps = FakeApps()
    let before = withBrew
    let (a, home) = try link(apps)
    let file = try barikConfig(before, in: home)
    try a.turnOn()
    // A copy gone at quit leaves the path to one that stays.
    moved(a, to: "/Volumes/mielwm/mielwm.app/Contents/Helpers/aerospace").resume()
    #expect(try read(file).contains("aerospace.path = \"\(shim)\""))
    let b = moved(a, to: shimB)
    b.resume()
    #expect(try read(file) == before.replacingOccurrences(of: brew, with: "\"\(shimB)\""))
    #expect(apps.helperRunning && apps.relaunched == 0) // Barik isn't running
    try b.turnOff()
    #expect(try read(file) == before)

    // A path the user set since is theirs.
    b.resume()
    #expect(try read(file) == before)
}

@MainActor @Test func aCopyThatMovesAwayAtQuitDoesNotTurnOn() throws {
    for place in ["/private/var/folders/xy/T/AppTranslocation/1234/d/mielwm.app", "/Volumes/mielwm/mielwm.app"] {
        let apps = FakeApps()
        let (barik, home) = try link(apps, shim: place + "/Contents/Helpers/aerospace")
        let file = try barikConfig(original, in: home)
        #expect(barik.temporaryLocation)
        #expect(throws: BarikLink.Problem.temporaryLocation) { try barik.turnOn() }
        #expect(try read(file) == original && !apps.helperRunning)
    }
    let (installed, _) = try link(FakeApps())
    #expect(!installed.temporaryLocation)
}

@MainActor @Test func offKeepsTheHelperWhenTheConfigCannotBeRead() throws {
    let apps = FakeApps()
    apps.barik = .distantPast
    let (barik, home) = try link(apps)
    let file = try barikConfig(original, in: home)
    try barik.turnOn()
    try Data([0xFF, 0xFE, 0x00]).write(to: file)
    #expect(throws: (any Error).self) { try barik.turnOff() }
    #expect(apps.helperRunning && apps.relaunched == 1)
}
