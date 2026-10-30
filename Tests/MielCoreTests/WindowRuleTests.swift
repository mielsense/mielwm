import Foundation
@testable import MielCore
import Testing

// Window rules by app name and title.

@Test func windowRulesLoadNestedOrFlatAndReportMistakes() {
    let loaded = parseSettings(config: Data("""
    {
      "rules": { "pip": { "title": "Picture-in-Picture", "floating": true } },
      "rules:zoom:app": "^zoom",
      "rules:zoom:workspace": 3,
      "rules:bad:title": "([",
      "rules:bad2:color": "red",
      "rules:bad3:workspace": 12,
      "rules:nofield": true
    }
    """.utf8))
    #expect(loaded.settings.windowRules["pip"] == WindowRule(title: "Picture-in-Picture", floating: true))
    #expect(loaded.settings.windowRules["zoom"] == WindowRule(app: "^zoom", workspace: 3))
    #expect(loaded.settings.windowRules.count == 2)
    #expect(loaded.errors.count == 4)
}

@Test func windowRulesFloatOrPlaceByNameAndTitle() {
    var settings = testSettings(layout: .tiles)
    settings.windowRules = [
        "pip": WindowRule(appID: "org.mozilla.firefox", title: "picture-in-picture", floating: true),
        "zoom": WindowRule(app: "^zoom", workspace: 3),
        "empty": WindowRule(floating: true), // no matcher: matches nothing
    ]
    let s = tilingState([
        snapshot(1, onBuiltIn, title: "Picture-in-Picture", app: "Firefox", bundle: "org.mozilla.firefox"),
        snapshot(2, onBuiltIn, title: "Picture-in-Picture", app: "Safari", bundle: "com.apple.Safari"), // other app
        snapshot(3, onBuiltIn, title: "Meeting", app: "zoom.us", bundle: "us.zoom.xos"),
        snapshot(4, onBuiltIn),
    ], settings: settings)
    #expect(s.window(wid(1))?.workspace == nil)
    #expect(s.window(wid(2))?.workspace == 1)
    #expect(s.window(wid(3))?.workspace == 3)
    #expect(s.window(wid(4))?.workspace == 1)
}

@Test func windowRulesGoInNumberOrderAndKeepTheirWorkspacesFreeAtStartup() {
    var settings = testSettings(layout: .tiles)
    settings.windowRules = ["rule-10": WindowRule(app: "ghostty", workspace: 4), "rule-2": WindowRule(app: "ghostty", workspace: 2)]
    #expect(settings.windowRule(for: snapshot(1, onBuiltIn))?.workspace == 2)
    settings.windowRules = ["zoom": WindowRule(app: "zoom", workspace: 1)]
    let s = makeState([snapshot(1, onBuiltIn)], settings: settings) // at startup each window gets a free workspace
    #expect(s.window(wid(1))?.workspace == 2)
}

@Test func aRuleThatDoesNothingDoesNotHideALaterOne() {
    var settings = Settings()
    settings.windowRules = ["a-matcher-only": WindowRule(app: "ghostty"), "b": WindowRule(app: "ghostty", workspace: 2)]
    #expect(settings.windowRule(for: snapshot(1, onBuiltIn)) == WindowRule(app: "ghostty", workspace: 2))
}

@Test func aRulesWorkspaceWinsOverTheFloatingAppsAndLayout() {
    var settings = testSettings(layout: .tiles)
    settings.floatingApps = "us.zoom.xos"
    settings.windowRules = ["zoom": WindowRule(app: "zoom", workspace: 3), "pip": WindowRule(title: "pip", floating: true, workspace: 4)]
    let zoom = snapshot(1, onBuiltIn, title: "Meeting", app: "zoom.us", bundle: "us.zoom.xos")
    let pip = snapshot(2, onBuiltIn, title: "PiP", app: "Zoom PiP", bundle: "us.zoom.xos")
    var s = tilingState([zoom, pip], settings: settings)
    #expect(s.window(wid(1))?.workspace == 3) // the rule, not the app's place on the floating list
    #expect(s.window(wid(2))?.workspace == nil) // floating wins in a rule that says both
    settings.defaultLayout = .floating
    s = tilingState([zoom], settings: settings)
    #expect(s.window(wid(1))?.workspace == 3)
}
