import Foundation
@testable import MielCore
import Testing
import TOMLDecoder

// Barik: the `aerospace` commands answered from the canvas, and the edit to
// Barik's config. Both are read back with Barik's own models (BarikModels.swift).

// MARK: Commands

private func decoded<T: Decodable>(_ reply: AeroSpaceReply, as: T.Type) throws -> T {
    guard case let .output(json) = reply else { throw CocoaError(.coderInvalidValue) }
    return try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

private let windowsAll = ["list-windows", "--all", "--json", "--format", "%{window-id} %{app-name} %{window-title} %{workspace}"]

@Test func barikReadsWorkspacesAndWindowsInItsOwnModels() throws {
    var s = twoTiles()
    _ = s.send(.system(.windowFocused(wid(2))))
    _ = s.send(.action(.moveToWorkspace(3))) // window 2 to workspace 3
    let current = try #require(s.currentWorkspace)

    let spaces = try decoded(s.aerospace(["list-workspaces", "--all", "--json"]), as: [AeroSpace].self)
    #expect(spaces.map(\.workspace) == s.workspaces.map(\.slot).sorted().map(String.init))
    #expect(spaces.map(\.workspace).contains("1") && spaces.map(\.workspace).contains("3"))
    let focusedSpace = try decoded(s.aerospace(["list-workspaces", "--focused", "--json"]), as: [AeroSpace].self)
    #expect(focusedSpace.map(\.workspace) == [String(current)])

    let windows = try decoded(s.aerospace(windowsAll), as: [AeroWindow].self)
    #expect(Set(windows.map(\.id)) == [1, 2])
    for w in windows {
        #expect(w.workspace == s.window(wid(UInt32(w.id)))?.workspace.map(String.init))
        #expect(w.appName == "Ghostty" && w.title == "Ghostty \(w.id)")
    }
    #expect(windows.first { $0.id == 2 }?.workspace == "3")
    let focused = try decoded(s.aerospace(["list-windows", "--focused", "--json"]), as: [AeroWindow].self)
    #expect(focused.map(\.id) == [Int(try #require(s.focused).number)])
}

@Test func floatingWindowsAreNotListedButCanBeFocused() throws {
    var s = twoTiles()
    _ = s.send(.action(.toggleFloating)) // window 1, focused, floats
    let windows = try decoded(s.aerospace(windowsAll), as: [AeroWindow].self)
    #expect(windows.map(\.id) == [2])
    let focused = try decoded(s.aerospace(["list-windows", "--focused", "--json"]), as: [AeroWindow].self)
    #expect(focused.map(\.id) == [1] && focused.first?.workspace == nil)
}

@Test func barikClicksBecomeTheCanvasActions() {
    var s = twoTiles()
    #expect(s.aerospace(["workspace", "3"]) == .input(.action(.workspace(3))))
    #expect(s.aerospace(["focus", "--window-id", "2"]) == .input(.landOn(wid(2))))
    #expect(s.aerospace(["focus", "--window-id", "99"]) == .input(nil)) // closed since Barik listed it
    // The id Barik got from list-windows leads back to the window.
    _ = s.send(.landOn(wid(2)))
    #expect(s.focused == wid(2))
}

@Test func otherCommandsAreUnknown() {
    let s = twoTiles()
    for args in [[], ["list-monitors"], ["list-windows", "--json"], ["list-workspaces", "--all"], ["workspace", "next"],
                 ["focus", "left"], ["focus", "--window-id", "x"], ["move-node-to-workspace", "2"]] {
        #expect(s.aerospace(args) == .unknown, "\(args)")
    }
}

@Test func anEmptyCanvasListsNothing() throws {
    let s = makeState([])
    #expect(try decoded(s.aerospace(windowsAll), as: [AeroWindow].self).isEmpty)
    #expect(try decoded(s.aerospace(["list-windows", "--focused", "--json"]), as: [AeroWindow].self).isEmpty)
}

// MARK: Config

private let shim = "/Applications/mielwm.app/Contents/Helpers/aerospace"

/// aerospace.path as Barik's TOML decoder reads it.
private func barikPath(_ text: String) throws -> String? {
    struct Root: Decodable { var aerospace: AerospaceConfig? }
    return try TOMLDecoder().decode(Root.self, from: text).aerospace?.path
}

/// Barik reads the edited file, and switching off gives back the file as it was.
private func roundTrip(_ text: String, previous expected: String? = nil) throws -> String {
    let on = try #require(BarikConfig.pointing(text, to: shim))
    #expect(on.previous == expected)
    #expect(try barikPath(on.text) == shim)
    #expect(BarikConfig.restoring(on.text, from: shim, previous: on.previous) == text)
    let again = try #require(BarikConfig.pointing(on.text, to: shim)) // on twice: no change
    #expect(again.text == on.text)
    return on.text
}

@Test func bariksDefaultConfigGetsThePathAboveItsFirstTable() throws {
    let edited = try roundTrip(barikDefaultConfig)
    #expect(edited.contains("theme = \"system\" # system, light, dark\n\naerospace.path = \"\(shim)\"\n\n[widgets]\n"))
    #expect(edited.replacingOccurrences(of: "aerospace.path = \"\(shim)\"\n\n", with: "") == barikDefaultConfig)
    let root = try TOMLDecoder().decode(RootToml.self, from: edited)
    #expect(root.aerospace?.path == shim)
    #expect(root.widgets.displayed.map(\.id) == ["default.spaces", "spacer", "default.network", "default.battery", "divider", "default.time"])
    #expect(root.theme == "system")
}

@Test func anEmptyConfigGetsOneLine() throws {
    let edited = try roundTrip("")
    #expect(edited == "aerospace.path = \"\(shim)\"\n")
    struct Aerospace: Decodable { var aerospace: AerospaceConfig } // Barik itself needs [widgets]
    #expect(try TOMLDecoder().decode(Aerospace.self, from: edited).aerospace.path == shim)
}

@Test func anExistingTopLevelPathIsReplacedAndComesBack() throws {
    let text = "aerospace.path = \"/opt/homebrew/bin/aerospace\" # from brew\n" + barikDefaultConfig
    let edited = try roundTrip(text, previous: "\"/opt/homebrew/bin/aerospace\"")
    #expect(edited.hasPrefix("aerospace.path = \"\(shim)\" # from brew\n"))
    #expect(try TOMLDecoder().decode(RootToml.self, from: edited).aerospace?.path == shim)
}

@Test func anAerospaceTableKeepsItsPathThere() throws {
    let text = barikDefaultConfig + "\n\n[aerospace]\n  path = '/usr/local/bin/aerospace'   # mine\n"
    let edited = try roundTrip(text, previous: "'/usr/local/bin/aerospace'")
    #expect(edited.hasSuffix("[aerospace]\n  path = \"\(shim)\"   # mine\n"))
    #expect(try TOMLDecoder().decode(RootToml.self, from: edited).aerospace?.path == shim)

    let bare = barikDefaultConfig + "\n\n[aerospace]\n# nothing yet\n"
    let filled = try roundTrip(bare)
    #expect(filled.hasSuffix("[aerospace]\npath = \"\(shim)\"\n# nothing yet\n"))
    #expect(try TOMLDecoder().decode(RootToml.self, from: filled).aerospace?.path == shim)
}

@Test func commentsBlanksAndArraysStayAsTheyWere() throws {
    let text = """
        # my bar
        # aerospace.path = "/somewhere/else"

        theme = "dark"   # dark always
        extra = [
          ["not", "a table"],  # [nor this]
          "x # y",
        ]

        [widgets]
        displayed = ["default.spaces"] # just spaces

        """
    let edited = try roundTrip(text)
    #expect(edited.contains("# aerospace.path = \"/somewhere/else\"\n"))
    #expect(edited.contains("  \"x # y\",\n]\n\naerospace.path = \"\(shim)\"\n\n[widgets]\n"))
    struct Root: Decodable { var aerospace: AerospaceConfig?; var widgets: WidgetsSection; var theme: String }
    let root = try TOMLDecoder().decode(Root.self, from: edited)
    #expect(root.aerospace?.path == shim && root.theme == "dark" && root.widgets.displayed.map(\.id) == ["default.spaces"])
}

@Test func oddPathsAreQuotedForTOML() throws {
    let odd = "/Users/a \"b\"/c\\d/mielwm.app/Contents/Helpers/aerospace"
    let edited = try #require(BarikConfig.pointing(barikDefaultConfig, to: odd)).text
    #expect(try TOMLDecoder().decode(RootToml.self, from: edited).aerospace?.path == odd)
    #expect(BarikConfig.restoring(edited, from: odd, previous: nil) == barikDefaultConfig)
}

@Test func switchingOffLeavesAPathTheUserChangedSince() throws {
    let on = try #require(BarikConfig.pointing(barikDefaultConfig, to: shim)).text
    let theirs = on.replacingOccurrences(of: shim, with: "/opt/homebrew/bin/aerospace")
    #expect(BarikConfig.restoring(theirs, from: shim, previous: nil) == theirs)
}

@Test func anInlineAerospaceTableIsLeftToTheUser() {
    #expect(BarikConfig.pointing("aerospace = { path = \"/x\" }\n" + barikDefaultConfig, to: shim) == nil)
}

@Test func barikReadsTheDotFileFirst() {
    let home = URL(fileURLWithPath: "/Users/u")
    #expect(BarikConfig.candidates(home: home).map(\.path) == ["/Users/u/.barik-config.toml", "/Users/u/.config/barik/config.toml"])
}

// Another copy of mielwm.app: moved, translocated, or run from the disk image.
private let otherShim = "/Users/u/Applications/mielwm.app/Contents/Helpers/aerospace"

@Test func anyMielwmCommandIsMielwmsOwn() throws {
    let text = "aerospace.path = \"/Users/u/Applications/mielwm.app/Contents/Helpers/aerospace\"\n" + barikDefaultConfig
    #expect(BarikConfig.restoring(text, from: shim, previous: "'/opt/homebrew/bin/aerospace'")
        == "aerospace.path = '/opt/homebrew/bin/aerospace'\n" + barikDefaultConfig)
    let literal = "aerospace.path = '/Applications/mielwm 2.app/Contents/Helpers/aerospace'\n" + barikDefaultConfig
    #expect(BarikConfig.restoring(literal, from: shim, previous: nil) == barikDefaultConfig)
    // A path that only looks alike stays.
    let brew = "aerospace.path = \"/opt/homebrew/Contents/Helpers/aerospace-x\"\n" + barikDefaultConfig
    #expect(BarikConfig.restoring(brew, from: shim, previous: nil) == brew)
}

@Test func anotherCopysCommandIsNeverThePreviousPath() throws {
    let a = try #require(BarikConfig.pointing(barikDefaultConfig, to: otherShim))
    #expect(a.previous == nil && !a.wasMielwm)
    let b = try #require(BarikConfig.pointing(a.text, to: shim))
    #expect(b.previous == nil && b.wasMielwm)
    #expect(try barikPath(b.text) == shim)
    let mine = try #require(BarikConfig.pointing("aerospace.path = '/opt/homebrew/bin/aerospace'\n", to: shim))
    #expect(mine.previous == "'/opt/homebrew/bin/aerospace'" && !mine.wasMielwm)
}
