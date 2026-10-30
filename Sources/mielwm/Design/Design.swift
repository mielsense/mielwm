import AppKit
import MielCore
import SwiftUI

/// mielwm's design language for its native windows: Settings, onboarding,
/// About, sheets and alerts. The values follow System Settings on macOS 26.
enum Design {
    // MARK: Type. SF Pro only, regular or semibold, never all caps.

    /// The pane's name in its header card.
    static let headerTitle = Font.system(size: 22, weight: .semibold)
    /// A row's title, and body text.
    static let row = Font.system(size: rowSize)
    /// Text under a row or a group, labels under thumbnails.
    static let secondary = Font.system(size: secondarySize)
    /// Their sizes, for what AppKit draws and what scales (the overview's chrome, the notices).
    static let rowSize: CGFloat = 13, secondarySize: CGFloat = 11

    // MARK: Spacing, on a 4 pt grid.

    enum Space {
        static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, xl: CGFloat = 20, xxl: CGFloat = 24
    }

    // MARK: Radii, all continuous.

    enum Radius {
        /// A grouped box of rows outside a Form (onboarding's steps).
        static let group: CGFloat = 12
        /// A thumbnail in a visual picker.
        static let thumbnail: CGFloat = 8
        /// Buttons, fields, key caps.
        static let control: CGFloat = 6
        /// An icon tile of `size` points: 5 at 20, 5 at 24, 11 at 48.
        static func tile(_ size: CGFloat) -> CGFloat { (size * 0.225).rounded() }
    }

    // MARK: Fills. Surfaces separate by fill, not by strokes.

    /// A grouped box of rows outside a Form.
    static let groupFill = Color(nsColor: .quaternarySystemFill)
    /// Increase Contrast draws an edge around filled shapes.
    static func edge(_ contrast: ColorSchemeContrast) -> Color { contrast == .increased ? Color(nsColor: .separatorColor) : .clear }

    // MARK: Icon tiles

    /// Apple's tile colors, the same in light and dark.
    enum Tint {
        static let gray = Color(red: 0.56, green: 0.56, blue: 0.59)
        static let graphite = Color(red: 0.17, green: 0.17, blue: 0.18)
        static let blue = Color(red: 0.04, green: 0.48, blue: 1)
        static let indigo = Color(red: 0.35, green: 0.34, blue: 0.84)
        static let cyan = Color(red: 0.2, green: 0.68, blue: 0.9)
        static let green = Color(red: 0.2, green: 0.78, blue: 0.35)
        static let orange = Color(red: 1, green: 0.58, blue: 0)
        static let red = Color(red: 1, green: 0.23, blue: 0.19)
    }

    /// Tile sizes: the sidebar, a row, a header card.
    enum Tile {
        static let sidebar: CGFloat = 20, row: CGFloat = 24, header: CGFloat = 48
        /// The glyph's box, as a share of the tile.
        static let glyph: CGFloat = 0.62
    }

    // MARK: Key caps
    //
    // How shortcuts look wherever they appear: the Keyboard pane, the menu's
    // hints, onboarding, the overview's HUD, the notices and the canvas. The
    // numbers are `KeyCapMetrics` in MielCore, so MielRender draws the same.
    // `KeyCaps` draws them in SwiftUI; the notices and the canvas draw them
    // by hand from the same values.

    enum KeyCap {
        typealias M = KeyCapMetrics
        static let textSize = M.textSize, tracking = M.tracking
        static let radius = M.radius
        static let padding = EdgeInsets(top: M.paddingDown, leading: M.paddingAcross, bottom: M.paddingDown, trailing: M.paddingAcross)
        static let minHeight = M.minHeight
        static let text = M.textOpacity
        static let rest = M.rest, hover = M.hover, onAccent = M.onAccent

        /// The fill at rest on `material`: more on glass and frosted panels, which let the backdrop through.
        static func fill(on material: ChromeMaterial) -> Double { material == .solid ? M.rest : M.onGlass }
    }

    /// A floating pill with one line in it: a toast in the overview or over the desktop.
    enum Pill {
        static let height: CGFloat = 36
    }

    // MARK: Motion

    /// Changing pane: a short cross-fade. Controls change instantly.
    static func paneChange(reduceMotion: Bool) -> Animation { .easeOut(duration: reduceMotion ? 0.1 : 0.15) }
    /// A drawing that follows a value, like the gaps diagram. Nothing moves with Reduce Motion.
    static func follow(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .spring(duration: 0.3, bounce: 0) }

    // MARK: Materials

    /// What the overview's chrome and the notices are made of: Liquid glass
    /// (macOS 26 and later), the frosted HUD material, or a solid fill with
    /// Reduce Transparency. The "Glass style" setting (`appearance:glass`)
    /// chooses between the first two.
    enum ChromeMaterial: Equatable {
        case glass, hud, solid

        static func current(_ look: Look) -> ChromeMaterial {
            if look.reduceTransparency { return .solid }
            if look.liquid, #available(macOS 26, *) { return .glass }
            return .hud
        }
    }
}

extension View {
    /// A floating surface in `shape`: Liquid glass or a frosted material, per `style`.
    @ViewBuilder func glassSurface(_ style: GlassStyle, in shape: some Shape) -> some View {
        if #available(macOS 26, *), style == .liquid {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }
}
