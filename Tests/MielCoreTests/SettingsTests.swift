import CoreGraphics
import Foundation
@testable import MielCore
import Testing

func json(_ text: String) -> Data { Data(text.utf8) }

/// One folder per run, deleted when the run ends. Its own, so runs in other checkouts leave it alone.
private let testRoot: URL = {
    atexit { try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("mielwm-tests-\(getpid())")) }
    return FileManager.default.temporaryDirectory.appendingPathComponent("mielwm-tests-\(getpid())", isDirectory: true)
}()

func tempDir() throws -> URL {
    let url = testRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

// MARK: Config

@Test func configDefaultsMatchUpstream() {
    let loaded = parseSettings(config: nil)
    #expect(loaded.errors.isEmpty && loaded.settings == Settings())
    let s = loaded.settings
    #expect(s.minZoom == 0.05 && s.maxZoom == 2.5 && s.zoomStep == 0.12 && s.initialZoom == 0.72)
    #expect(s.placementGap == 40 && s.gap == 12 && s.look.gridSize == 80)
    #expect(s.arrangeSizeSimilarity == 0.12 && s.arrangeResizeLimit == 0.15)
    #expect(s.moveModifiers == [.control, .option])
    #expect(s.chords[KeyChord(modifiers: [.control, .option], key: "g")] == .toggleOverview)
    #expect(s.chords[KeyChord("opt+shift+left")!] == .nudge(.left))
    #expect(s.chords[KeyChord("opt+1")!] == .workspace(1)) // AeroSpace's keys
    #expect(s.chords[KeyChord("opt+shift+9")!] == .moveToWorkspace(9))
    #expect(s.chords[KeyChord("opt+0")!] == .noop) // must not type º
    #expect(s.resolvedLook().accent == .mielOrange)
}

@Test func configOverrides() {
    let loaded = parseSettings(config: json("""
    {
      "canvas": {"initial_zoom": 0.5, "grid_size": 100},
      "navigator:accent": "cyan",
      "input": {"move_modifier": "cmd+opt"},
      "keys:opt+ctrl+g": "fit",
      "keys:opt+o": "none"
    }
    """))
    #expect(loaded.errors.isEmpty)
    let s = loaded.settings
    #expect(s.initialZoom == 0.5 && s.look.gridSize == 100)
    #expect(s.resolvedLook().accent == parseHexColor("#22d3ee"))
    #expect(s.moveModifiers == [.command, .option])
    #expect(s.chords[KeyChord("ctrl+opt+g")!] == .fit)
    #expect(s.bindings.keys.filter { KeyChord($0) == KeyChord("ctrl+opt+g") }.count == 1)
    #expect(s.chords[KeyChord("opt+o")!] == nil) // unbound
}

@Test func badJSONFallsBackToDefaultsWithAnError() {
    let loaded = parseSettings(config: json("{ nope"))
    #expect(loaded.errors.count == 1 && loaded.errors[0].hasPrefix("config.json: not valid JSON"))
    #expect(loaded.settings == Settings())
}

@Test func badKeysCostOnlyThemselves() {
    let loaded = parseSettings(config: json("""
    {"canvas:initial_zoom": "big", "nonsense": 1, "keys:ctrl+opt+q": "explode", "keys:hyper+q": "fit",
     "navigator:accent": "plaid", "canvas:max_zoom": 99, "window:shadow": false}
    """))
    #expect(loaded.errors.count == 5)
    #expect(loaded.settings.initialZoom == 0.72 && loaded.settings.accent == "auto")
    #expect(loaded.settings.maxZoom == 10) // clamped to its range
    #expect(!loaded.settings.look.windowShadow)
}

@Test func oldHUDKeysStillLoad() {
    // The mono HUD's settings no longer draw anything, but old configs must load cleanly.
    let loaded = parseSettings(config: json("""
    {"navigator": {"mono_font": "JetBrains Mono", "uppercase": true, "letter_spacing": 1.5, "search_glow": 0.3,
                   "search_border": 2, "search_border_color": "accent"}}
    """))
    #expect(loaded.errors.isEmpty)
}

@Test func autoAccentFollowsTheSystem() {
    var s = Settings()
    s.accent = "auto"
    #expect(s.resolvedLook(systemAccent: RGB(0, 0, 1)).accent == RGB(0, 0, 1))
    #expect(s.resolvedLook().accent == .mielOrange)
    #expect(accentPresets.count == 18 && accentColor("#ABCDEF") == parseHexColor("abcdef"))
}

@Test func filesLoadFromInjectedPaths() throws {
    let dir = try tempDir()
    let paths = ConfigPaths(config: dir.appendingPathComponent("config.json"))
    #expect(loadSettings(paths).settings == Settings()) // a missing file is fine
    try json(#"{"distortion": {"strength": 0.2}, "blur": true}"#).write(to: paths.config)
    let loaded = loadSettings(paths)
    #expect(loaded.errors.isEmpty)
    #expect(loaded.settings.look.lensStrength == 0.2 && loaded.settings.look.blur)
    #expect(ConfigPaths.standard(home: URL(fileURLWithPath: "/Users/x")).config.path == "/Users/x/.config/mielwm/config.json")
}

@Test func chordsParseInAnyOrderAndSpelling() {
    #expect(KeyChord("opt+ctrl+g") == KeyChord("ctrl+opt+g"))
    #expect(KeyChord("Control + Option + G") == KeyChord("ctrl+opt+g"))
    #expect(KeyChord("alt+-") == KeyChord("opt+minus"))
    #expect(KeyChord("ctrl+") == nil && KeyChord("hyper+g") == nil && KeyChord("ctrl+nokey") == nil)
    #expect(KeyChord("opt+ctrl+g")?.description == "ctrl+opt+g")
    #expect(KeyChord("opt+ctrl+g")?.symbol == "⌃⌥G")
}

@Test func actionCommandsRoundTrip() {
    var actions: [Action] = [.toggleOverview, .search(nil), .search("fast fetch"), .tune, .help, .switchWindow(forward: true),
                             .switchWindow(forward: false), .zoomIn, .zoomOut, .fit, .frame, .summon, .land, .back, .fill,
                             .fullscreen, .pin, .grow, .shrink, .arrange, .undo, .redo, .refresh, .noop,
                             .layoutTiles, .layoutStack, .toggleFloating, .workspace(3), .workspaceStep(forward: true),
                             .workspaceStep(forward: false), .moveToWorkspace(9), .workspaceBackAndForth, .settings, .close, .minimize,
                             .resize(.smart, 50), .resize(.width, -100), .resize(.height, 20)]
    for d in Direction.allCases { actions += [.focus(d), .nudge(d), .pan(d)] }
    for a in actions { #expect(Action(command: a.command) == a, "\(a.command)") }
    #expect(Action(command: "explode") == nil && Action(command: "focus sideways") == nil && Action(command: "close now") == nil)
}

// MARK: Layout persistence

@Test func layoutRoundTripsAndWindowsComeBack() throws {
    var s = makeState([snapshot(1, onBuiltIn, title: "zsh"), snapshot(2, onBuiltIn.offsetBy(dx: 40, dy: 40), title: "zsh"),
                       snapshot(3, onExternal, title: "fastfetch")])
    _ = s.send(.system(.windowFocused(wid(1))))
    _ = s.send(.action(.nudge(.right)))
    _ = panDesk(&s, dx: -2500) // window 3 stays on screen, 1 and 2 park
    let layout = LayoutSnapshot(s)
    #expect(layout.windows.map(\.ordinal) == [0, 0, 1]) // back to front: focusing 1 raised it
    #expect(layout.windows.filter(\.parked).count == 2)

    let url = try tempDir().appendingPathComponent("layout.json")
    try layout.save(to: url)
    let loaded = try #require(LayoutSnapshot.load(from: url))
    #expect(loaded == layout)

    // Next run: new window numbers, same apps and titles, found where we parked them.
    var next = CanvasState(screens: [builtIn, external], settings: testSettings(), ownPID: 1, savedLayout: loaded)
    #expect(next.deskCamera == s.deskCamera)
    for w in layout.windows {
        _ = next.send(.system(.windowAppeared(snapshot(w.id!.number + 10, w.deskFrame, title: w.title))))
    }
    #expect(next.canvasFrame(11) == s.canvasFrame(1))
    #expect(next.canvasFrame(12) == s.canvasFrame(2))
    #expect(next.canvasFrame(13) == s.canvasFrame(3))
    #expect(next.window(wid(11))?.parked == true)
}

@Test func damagedLayoutIsIgnored() throws {
    let url = try tempDir().appendingPathComponent("layout.json")
    try json("{\"version\": 1, \"camera\": 7}").write(to: url)
    #expect(LayoutSnapshot.load(from: url) == nil)
    #expect(LayoutSnapshot.load(from: url.appendingPathExtension("missing")) == nil)
}

@Test func crashRecoveryUnparksWhatTheLayoutHadParked() throws {
    var s = makeState([snapshot(1, onBuiltIn), snapshot(2, onExternal)])
    _ = panDesk(&s, dx: -2500)
    let commands = unparkCommands(LayoutSnapshot(s), screens: [builtIn, external])
    #expect(moves(commands).keys.sorted { $0.number < $1.number } == [wid(1)])
    for frame in moves(commands).values { #expect(!isHiddenFrame(frame, screens: [builtIn, external])) }
}

// MARK: Camera animation

@Test func springConvergesWithoutOvershoot() {
    var a = CameraAnimator(camera: Camera(center: .zero), now: 0)
    a.fly(to: Camera(center: CGPoint(x: 1000, y: -500), zoom: 0.25), transition: 1, now: 0)
    var lastX = 0.0
    var t = 0.0
    while t < 2 {
        t += 1.0 / 120
        a.step(to: t)
        #expect(a.camera.center.x >= lastX - 1e-9 && a.camera.center.x <= 1000 + 1e-9)
        lastX = a.camera.center.x
    }
    #expect(a.isSettled)
    #expect(a.camera == Camera(center: CGPoint(x: 1000, y: -500), zoom: 0.25) && a.transition == 1)
}

@Test func springRetargetMidFlightKeepsPositionAndVelocity() {
    var a = CameraAnimator(camera: Camera(center: .zero), now: 0)
    a.fly(to: Camera(center: CGPoint(x: 1000, y: 0)), now: 0)
    a.step(to: 0.2)
    let here = a.camera.center.x, speed = a.x.velocity
    #expect(here > 0 && here < 1000 && speed > 0)
    a.fly(to: Camera(center: CGPoint(x: -1000, y: 0)), now: 0.2)
    #expect(a.camera.center.x == here && a.x.velocity == speed) // no jump
    a.step(to: 0.2 + 1.0 / 120)
    #expect(a.camera.center.x > here) // still coasting forward for a moment
    a.step(to: 3)
    #expect(a.isSettled && a.camera.center.x == -1000)
}

@Test func bezierFlightEndsOnTimeAndRestartsFromWhereItIs() {
    var a = CameraAnimator(camera: Camera(center: .zero), now: 0, curve: .bezier, duration: 0.8)
    a.fly(to: Camera(center: CGPoint(x: 800, y: 0)), now: 0)
    a.step(to: 0.4)
    let mid = a.camera.center.x
    #expect(mid > 400 && mid < 800) // ease-out: well past half way at half time
    a.fly(to: Camera(center: CGPoint(x: 0, y: 0)), now: 0.4)
    #expect(a.camera.center.x == mid)
    a.step(to: 1.2)
    #expect(a.camera.center.x == 0 && a.isSettled)
}

@Test func animationOffJumps() {
    var a = CameraAnimator(camera: Camera(center: .zero), now: 0)
    a.enabled = false
    a.fly(to: Camera(center: CGPoint(x: 10, y: 20), zoom: 0.5), transition: 1, now: 0)
    #expect(a.camera == Camera(center: CGPoint(x: 10, y: 20), zoom: 0.5) && a.isSettled && a.transition == 1)
}

@Test func reducerFlightsAreAnimatedWhenOn() {
    var s = makeState([snapshot(1, onBuiltIn)], settings: testSettings(animated: true))
    _ = s.send(.action(.toggleOverview))
    let zoom = s.animator.target.zoom
    #expect(s.camera.zoom == 1 && zoom <= 0.72 && s.needsOverlay && s.needsTicks)
    _ = s.advance(0.4)
    #expect(s.camera.zoom < 1 && s.camera.zoom > zoom && s.transition > 0.5)
    _ = s.advance(2)
    #expect(abs(s.camera.zoom - zoom) < 1e-9 && s.transition == 1)
}

// MARK: Lens and minimap

@Test func lensMatchesTheShaderFormula() {
    let look = Look(), size = CGSize(width: 1000, height: 500)
    let corner = lensSourcePoint(.zero, screenSize: size, look: look, transition: 1)
    let f = (1 + 0.14 * 2) / 1.08
    #expect(abs(corner.x - (0.5 - f * 0.5) * 1000) < 1e-9 && abs(corner.y - (0.5 - f * 0.5) * 500) < 1e-9)
    #expect(lensSourcePoint(CGPoint(x: 500, y: 250), screenSize: size, look: look, transition: 1) == CGPoint(x: 500, y: 250))
    #expect(lensSourcePoint(CGPoint(x: 10, y: 10), screenSize: size, look: look, transition: 0) == CGPoint(x: 10, y: 10))
    var off = look
    off.lensEnabled = false
    #expect(lensSourcePoint(CGPoint(x: 10, y: 10), screenSize: size, look: off, transition: 1) == CGPoint(x: 10, y: 10))
    var power = look
    power.lensTransitionPower = 2
    #expect(lensProgress(look: power, transition: 0.5) == 0.25)
}

@Test func lensRoundTrips() {
    var strong = Look()
    strong.lensStrength = -0.15 // stronger inward bends fold the corners and have no inverse there
    strong.lensEdgeScale = 1.3
    for look in [Look(), strong] {
        for transition in [0.3, 1.0] {
            for x in stride(from: 0.0, through: 1512, by: 151.2) {
                for y in stride(from: 0.0, through: 982, by: 98.2) {
                    let p = CGPoint(x: x, y: y)
                    let source = lensSourcePoint(p, screenSize: builtIn.frame.size, look: look, transition: transition)
                    let back = lensScreenPoint(source, screenSize: builtIn.frame.size, look: look, transition: transition)
                    #expect(abs(back.x - x) < 1e-6 && abs(back.y - y) < 1e-6)
                }
            }
        }
    }
}

@Test func minimapLayoutMatchesUpstreamAndRoundTrips() {
    let viewport = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let m = minimapLayout(screenSize: builtIn.frame.size, look: Look(), windows: [CGRect(x: 0, y: 0, width: 1000, height: 1000)],
                          viewport: viewport)
    #expect(m.panel == CGRect(x: 1248, y: 808, width: 240, height: 150))
    #expect(m.arrangeButton == CGRect(x: 1204, y: 922, width: 36, height: 36))
    #expect(m.content == CGRect(x: 1260, y: 820, width: 216, height: 126))
    let pad = 1512 * 0.06
    #expect(m.worldBounds == CGRect(x: -pad, y: -pad, width: 1512 + 2 * pad, height: 1000 + 2 * pad))
    #expect(m.fit == min(216 / m.worldBounds.width, 126 / m.worldBounds.height))
    let p = CGPoint(x: 700, y: 300)
    let back = m.toCanvas(m.toPanel(p))
    #expect(abs(back.x - p.x) < 1e-9 && abs(back.y - p.y) < 1e-9)
    #expect(m.hit(CGPoint(x: 1215, y: 935)) == .arrange)
    #expect(m.hit(CGPoint(x: 100, y: 100)) == nil)
    if case let .jump(target)? = m.hit(m.viewport.center) {
        #expect(abs(target.x - viewport.midX) < 1e-6 && abs(target.y - viewport.midY) < 1e-6)
    } else {
        Issue.record("a click on the viewport marker should jump")
    }
}

@Test func minimapClickJumpsTheCameraThere() {
    var s = makeState([snapshot(1, onBuiltIn), snapshot(2, onExternal)])
    _ = s.send(.action(.toggleOverview))
    #expect(s.scene(for: builtIn).minimap != nil)
    let layout = s.minimapLayout(for: builtIn)
    let marker = layout.windows[1].center // window 2's marker
    guard case let .jump(target)? = layout.hit(marker) else { Issue.record("expected a jump"); return }
    _ = s.send(.gesture(.minimapJump(target)))
    let center = s.camera.toCanvas(s.freeAreaCenter, deskCenter: s.deskCenter)
    #expect(abs(center.x - onExternal.midX) < 1e-6 && abs(center.y - onExternal.midY) < 1e-6)
    _ = s.send(.action(.toggleOverview))
    #expect(s.scene(for: builtIn).minimap == nil) // gone at 100%
}

@Test func onlyMultiModifierOverviewChordsWarmTheCaptures() {
    var settings = Settings()
    settings.moveModifier = "cmd+ctrl" // ⌃⌥ also moves windows by default: see the next test
    #expect(settings.warmModifiers == [[.control, .option]]) // ⌃⌥G
    settings.bindings["ctrl+opt+g"] = "none"
    settings.bindings["opt+space"] = "overview" // ⌥ alone is held for ⌥1-9 and more
    settings.bindings["cmd+shift+f"] = "search"
    settings.bindings["ctrl+shift+left"] = "pan left" // not an overview chord
    #expect(settings.warmModifiers == [[.command, .shift]])
}

@Test func glassStyleIsLiquidOrFrostedAndReduceTransparencyWins() {
    var s = Settings()
    #expect(s.set(.text("Frosted"), forKey: "appearance:glass") == nil)
    #expect(s.look.glass == .frosted && s.value(forKey: "appearance:glass") == .text("frosted"))
    #expect(s.set(.text("shiny"), forKey: "appearance:glass") != nil)
    #expect(s.look.glass == .frosted) // a bad value changes nothing
    s.set(.text("liquid"), forKey: "appearance:glass")
    #expect(!s.look.liquid) // stored, but this Mac has no Liquid glass: frosted
    s.look.liquidGlassAvailable = true
    #expect(s.look.liquid)
    s.look.reduceTransparency = true
    #expect(!s.look.liquid)
    #expect(Settings().look.glass == .liquid) // the same default on every Mac
    #expect(Settings.keys.contains("appearance:glass"))
}

@Test func theMoveModifiersNeverWarmTheCaptures() {
    var settings = Settings()
    #expect(settings.warmModifiers.isEmpty) // ⌃⌥G, but ⌃⌥ is held for every modifier drag
    settings.bindings["cmd+shift+o"] = "overview"
    #expect(settings.warmModifiers == [[.command, .shift]])
    settings.moveModifier = "cmd+shift"
    #expect(settings.warmModifiers == [[.control, .option]])
}
