import AppKit
import MielCore
import SwiftUI

// Core's colours as AppKit and SwiftUI colours.

extension Color {
    init(_ c: RGB) { self.init(.sRGB, red: c.r, green: c.g, blue: c.b) }
}

extension NSColor {
    convenience init(_ c: RGB) { self.init(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1) }
}

extension RGB {
    /// Text on the accent: dark on a light one, white on the rest.
    var onAccent: NSColor { wantsDarkText ? NSColor(white: 0, alpha: 0.85) : .white }
}
