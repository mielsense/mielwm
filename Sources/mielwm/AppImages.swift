import AppKit

/// The workspace numbers as a template image: the current one knocked out
/// of a filled rounded square, the others plain. Drawn at any scale.
func workspaceIndicator(_ numbers: [Int], current: Int?) -> NSImage {
    let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    let cell = NSSize(width: 15, height: 15), gap: CGFloat = 2
    let size = NSSize(width: CGFloat(numbers.count) * (cell.width + gap) - gap, height: cell.height)
    let image = NSImage(size: size, flipped: false) { _ in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
        for (i, n) in numbers.enumerated() {
            let box = CGRect(x: CGFloat(i) * (cell.width + gap), y: 0, width: cell.width, height: cell.height)
            let text = "\(n)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            let width = text.size(withAttributes: attributes).width
            // Digits sit on the baseline and rise to the cap height: center that.
            let origin = CGPoint(x: box.midX - width / 2, y: ((box.midY - font.capHeight / 2) * 2).rounded() / 2 + font.descender)
            if n == current {
                NSColor.black.setFill()
                NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
                ctx.setBlendMode(.destinationOut)
                text.draw(at: origin, withAttributes: attributes)
                ctx.setBlendMode(.normal)
            } else {
                text.draw(at: origin, withAttributes: attributes)
            }
        }
        return true
    }
    image.isTemplate = true
    return image
}

/// A file from the app's resources: the bundle's, or Resources/ in the checkout, for a development build.
func resourceURL(_ name: String, extensions: [String]) -> URL? {
    for ext in extensions {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) { return url }
    }
    var dir = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent()
    for _ in 0 ..< 6 { // .build/<triple>/debug up to the checkout
        guard let d = dir else { break }
        for ext in extensions {
            let url = d.appendingPathComponent("Resources/\(name).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        dir = d.deletingLastPathComponent()
    }
    return nil
}

/// The menu bar glyph: the template in Resources (MenuBarIcon.pdf, or .png
/// with an @2x beside it), else an SF Symbol.
let menuBarIconImage: NSImage? = {
    guard let url = resourceURL("MenuBarIcon", extensions: ["pdf", "png"]), let image = NSImage(contentsOf: url) else {
        return NSImage(systemSymbolName: "rectangle.on.rectangle.dashed", accessibilityDescription: "mielwm")
    }
    if let retina = NSImageRep(contentsOf: url.deletingLastPathComponent().appendingPathComponent("MenuBarIcon@2x.png")), url.pathExtension == "png" {
        retina.size = image.size
        image.addRepresentation(retina)
    }
    let height: CGFloat = 18
    image.size = NSSize(width: (image.size.width * height / max(image.size.height, 1)).rounded(), height: height)
    image.isTemplate = true
    image.accessibilityDescription = "mielwm"
    return image
}()

extension NSAlert {
    /// An alert with the app icon (an unbundled build would show a folder).
    static func mielwm() -> NSAlert {
        let alert = NSAlert()
        alert.icon = appIcon()
        return alert
    }
}

/// The app icon: the bundle's, or Resources/AppIcon.icns beside a
/// development build, else the menu bar glyph on an icon-shaped tile.
func appIcon() -> NSImage {
    if Bundle.main.bundleURL.pathExtension == "app" { return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath) }
    if let url = resourceURL("AppIcon", extensions: ["icns"]), let image = NSImage(contentsOf: url) { return image }
    return NSImage(size: NSSize(width: 128, height: 128), flipped: false) { rect in
        let tile = rect.insetBy(dx: 12.5, dy: 12.5) // the margin and corner of macOS icons
        let path = NSBezierPath(roundedRect: tile, xRadius: 23, yRadius: 23)
        NSGradient(starting: NSColor(srgbRed: 0.36, green: 0.36, blue: 0.4, alpha: 1), ending: NSColor(srgbRed: 0.16, green: 0.16, blue: 0.19, alpha: 1))?
            .draw(in: path, angle: -90)
        let symbol = NSImage(systemSymbolName: "rectangle.on.rectangle.dashed", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 52, weight: .regular).applying(.init(paletteColors: [.white])))
        if let symbol {
            symbol.draw(in: NSRect(x: rect.midX - symbol.size.width / 2, y: rect.midY - symbol.size.height / 2, width: symbol.size.width, height: symbol.size.height))
        }
        return true
    }
}

@MainActor
var aboutOptions: [NSApplication.AboutPanelOptionKey: Any] {
    [
        .applicationName: "mielwm",
        .applicationVersion: appVersion,
        .version: "",
        .applicationIcon: appIcon(),
        .credits: NSAttributedString(string: "Every window on one endless canvas.", attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: { let p = NSMutableParagraphStyle(); p.alignment = .center; return p }(),
        ]),
    ]
}

var appVersion: String {
    let info = Bundle.main.infoDictionary
    guard let version = info?["CFBundleShortVersionString"] as? String else { return "Development build" }
    return (info?["CFBundleVersion"] as? String).map { "\(version) (\($0))" } ?? version
}
