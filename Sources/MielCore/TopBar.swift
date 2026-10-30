import CoreGraphics
import Foundation

/// A status bar along a display's top edge, like Barik or SketchyBar.
public struct TopBar: Hashable, Codable, Sendable {
    public var owner: String // the app's name
    public var height: Double // what it covers below the menu bar

    public init(owner: String, height: Double) {
        self.owner = owner
        self.height = height
    }
}

/// The bar among `windows` on `screen`: a window pinned to the top of the
/// display or just under the menu bar, at least 80% as wide as the
/// display and 20 to 80 pt tall. The tallest wins; nil when there is none.
public func topBar(among windows: [(owner: String, frame: CGRect)], on screen: ScreenInfo) -> TopBar? {
    let display = screen.frame, top = screen.visibleFrame.minY
    return windows.compactMap { owner, f -> TopBar? in
        guard abs(f.minY - display.minY) <= 2 || abs(f.minY - top) <= 2,
              f.intersection(display).width >= display.width * 0.8, (20 ... 80).contains(f.height) else { return nil }
        let height = (f.maxY - top).rounded()
        return height > 0 ? TopBar(owner: owner, height: height) : nil // all under an always-shown menu bar
    }.max { $0.height < $1.height }
}

/// The top gap: Automatic leaves room for a bar it finds, Same uses the
/// top edge's gap everywhere, Custom has its own number for every display
/// but the built-in one.
public enum TopGapMode: String, Codable, CaseIterable, Sendable {
    case auto, same, custom
}

/// What the menu bar shows: every workspace with windows, the current one, or the icon.
public enum MenuBarStyle: String, Codable, CaseIterable, Sendable {
    case all, current, icon
}

public extension Settings {
    /// The gap above the tiles on `screen`, in points below its visible frame's top.
    func topGap(on screen: ScreenInfo) -> Double {
        switch topGapMode {
        case .auto: gapOuterTop + (screen.topBar?.height ?? 0)
        case .same: gapOuterTop
        case .custom: screen.isBuiltIn ? gapOuterTop : gapOuterTopExternal
        }
    }
}
