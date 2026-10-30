import AppKit
@testable import mielwm
import Testing

// What the alerts say. They are built, never shown.

@MainActor @Test func turningOnWithoutBarikPromisesNoEdit() {
    let alert = AppDelegate.barikAlert(on: true, config: nil)
    #expect(alert.informativeText.contains("hidden helper called AeroSpace"))
    #expect(!alert.informativeText.contains("aerospace.path"))
    #expect(AppDelegate.barikAlert(on: false, config: nil).informativeText == "mielwm will quit its AeroSpace helper.")
}

@MainActor @Test func turningOnWithBarikNamesItsConfig() {
    let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/barik/config.toml")
    let on = AppDelegate.barikAlert(on: true, config: file, icon: true).informativeText
    #expect(on.contains("aerospace.path in ~/.config/barik/config.toml"))
    #expect(on.contains("menu bar item changes to its icon"))
    #expect(AppDelegate.barikAlert(on: false, config: file).informativeText.contains("put the old aerospace.path back in ~/.config/barik/config.toml"))
}

@MainActor @Test func configProblemsListEveryLine() {
    let alert = AppDelegate.configProblemsAlert(["one", "two"])
    #expect(alert.informativeText.hasPrefix("one\ntwo\n"))
    #expect(alert.buttons.map(\.title) == ["Open config file", "OK"])
}
