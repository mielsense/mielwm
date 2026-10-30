import AppKit
import MielCore

/// `--notice-preview`: draws the notice panels over a sample desktop and
/// saves each look as a PNG, then quits. No canvas, no event tap, nothing
/// moves, but the panels and the backdrop are on screen for a moment: glass
/// only renders there. The capture needs Screen Recording for the terminal.
@MainActor
func noticePreview(_ args: [String]) -> Never {
    NSApplication.shared.setActivationPolicy(.accessory)
    let out = URL(fileURLWithPath: value("--out", in: args) ?? "notice-preview", isDirectory: true)
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    guard let screen = NSScreen.main else { fail("no display") }
    let size = NSSize(width: 820, height: 460)
    let rect = NSRect(x: (screen.frame.midX - size.width / 2).rounded(), y: (screen.frame.midY - size.height / 2).rounded(),
                      width: size.width, height: size.height)

    let backdrop = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
    backdrop.level = .floating
    let desk = SampleDesk(frame: NSRect(origin: .zero, size: size))
    backdrop.contentView = desk

    let entries = [("com.apple.Safari", "Safari", "Apple Developer Documentation"), ("com.mitchellh.ghostty", "Ghostty", "~/code/mielwm"),
                   ("com.apple.dt.Xcode", "Xcode", "NoticePanel.swift"), ("com.apple.Notes", "Notes", "Groceries for the week and a long title")]
        .map { StackNotice.Entry(bundleID: $0.0, title: $0.2) }
    let stack = StackNotice(entries: entries, front: 1, area: .zero)
    let contents: [(NoticeContent, CGFloat, CGFloat)] = [ // content, its centre x, its top (from the backdrop's top)
        (.stack(stack), 0.5, 20),
        (.toast("Tidied 4 windows  {⌃⌥Z} Undo"), 0.5, 200),
        (.workspace(WorkspaceNotice(numbers: [1, 2, 3, 5, 9], current: 3, mode: .stack, windowCount: 4)), 0.5, 380),
    ]
    let panels = contents.map { _ in NoticePanel() }
    let accent = Settings().resolvedLook(systemAccent: nil).accent

    var looks: [(String, Design.ChromeMaterial, Bool)] = [("glass", .glass, false), ("hud", .hud, false), ("solid", .solid, false), ("glass-contrast", .glass, true)]
    if #unavailable(macOS 26) { looks.removeAll { $0.1 == .glass } }
    for (appearanceName, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
        NSApp.appearance = NSAppearance(named: appearance)
        for plain in [false, true] {
            desk.plain = plain
            desk.needsDisplay = true
            backdrop.orderFrontRegardless()
            for (name, material, contrast) in looks where !plain || material == .glass {
                for ((content, x, top), panel) in zip(contents, panels) {
                    let drawing = noticeDrawing(content, accent: accent, increaseContrast: contrast, maxWidth: rect.width - 48)
                    panel.show(drawing, center: rect.minX + rect.width * x, top: rect.maxY - top, material: material, increaseContrast: contrast)
                    panel.window.alphaValue = 1
                }
                pump(0.6)
                let file = out.appendingPathComponent("notices-\(name)\(plain ? "-plain" : "")-\(appearanceName).png")
                capture(rect, on: screen, to: file)
            }
        }
    }
    // A strip too wide for its titles: the others' titles go first.
    NSApp.appearance = NSAppearance(named: .darkAqua)
    desk.plain = false
    let many = StackNotice(entries: entries + entries + entries, front: 4, area: .zero)
    let drawing = noticeDrawing(.stack(many), accent: accent, increaseContrast: false, maxWidth: rect.width - 48)
    panels[0].show(drawing, center: rect.midX, top: rect.maxY - 20, material: looks[0].1, increaseContrast: false)
    panels.dropFirst().forEach { $0.hide() }
    pump(0.6)
    capture(rect, on: screen, to: out.appendingPathComponent("notices-crowded-dark.png"))
    print(out.path)
    exit(0)
}

/// The screen region under `rect` (AppKit points) as a PNG.
@MainActor
private func capture(_ rect: NSRect, on screen: NSScreen, to url: URL) {
    let top = (NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY) - rect.maxY
    screencapture("\(Int(rect.minX)),\(Int(top)),\(Int(rect.width)),\(Int(rect.height))", to: url)
}

/// A desktop to see the material against: a wallpaper gradient with two
/// windows of text, or (`plain`) the gradient alone.
private final class SampleDesk: NSView {
    var plain = false
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let colors = dark ? [NSColor(srgbRed: 0.10, green: 0.12, blue: 0.24, alpha: 1), NSColor(srgbRed: 0.35, green: 0.16, blue: 0.32, alpha: 1)]
            : [NSColor(srgbRed: 0.62, green: 0.78, blue: 0.95, alpha: 1), NSColor(srgbRed: 0.98, green: 0.80, blue: 0.70, alpha: 1)]
        NSGradient(colors: colors)?.draw(in: bounds, angle: -30)
        guard !plain else { return }
        let text = "The quick brown fox jumps over the lazy dog. mielwm tiles windows into workspaces on one endless canvas. "
        for (i, r) in [NSRect(x: 30, y: 30, width: 470, height: 400), NSRect(x: 420, y: 90, width: 370, height: 330)].enumerated() {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 18
            shadow.shadowOffset = NSSize(width: 0, height: -6)
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.set()
            (dark ? NSColor(white: 0.13, alpha: 1) : NSColor.white).setFill()
            NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12).fill()
            NSGraphicsContext.restoreGraphicsState()
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 3
            let body = NSAttributedString(string: String(repeating: text, count: 12), attributes: [
                .font: i == 0 ? NSFont.systemFont(ofSize: 13) : NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: i == 0 ? NSColor.labelColor : NSColor.systemGreen, .paragraphStyle: style,
            ])
            body.draw(with: r.insetBy(dx: 18, dy: 18), options: [.usesLineFragmentOrigin])
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: NSRect(x: r.maxX - 60, y: r.maxY - 60, width: 36, height: 36)).fill()
        }
    }
}
