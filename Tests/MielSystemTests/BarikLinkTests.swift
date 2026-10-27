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

@MainActor
private func link(_ apps: FakeApps) throws -> (BarikLink, home: URL) {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("mielwm-barik-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    let defaults = try #require(UserDefaults(suiteName: "mielwm-barik-test-\(UUID().uuidString)"))
    return (BarikLink(home: home, shim: shim, helper: URL(fileURLWithPath: "/x/AeroSpace.app"), apps: apps, defaults: defaults), home)
}

private func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

@MainActor @Test func withoutAConfigNothingIsWrittenOrStarted() throws {
    let apps = FakeApps()
    apps.barik = .distantPast
    let (barik, home) = try link(apps)
    #expect(barik.config == nil)
    #expect(throws: BarikLink.Problem.noConfig) { try barik.turnOn() }
    #expect(try FileManager.default.contentsOfDirectory(atPath: home.path).isEmpty)
    #expect(!apps.helperRunning && apps.relaunched == 0)
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
    let before = "aerospace.path = '/opt/homebrew/bin/aerospace'\n" + original
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
