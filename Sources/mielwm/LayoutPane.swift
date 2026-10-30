import AppKit
import MielCore
import MielSystem
import SwiftUI

struct LayoutPane: View {
    @EnvironmentObject var model: SettingsModel
    @StateObject private var gapFocus = GapFocus()

    var body: some View {
        let s = model.settings
        Form {
            Section { PaneHeader(pane: .layout) }
            Section {
                VisualPicker(title: "Layout", selection: Binding(get: { s.defaultLayout }, set: { model.set("layout:default", .text($0.rawValue)) }),
                             options: [LayoutMode.tiles, .stack, .floating], name: \.title) { LayoutThumbnail(layout: $0) }
                VisualPicker(title: "Orientation", selection: Binding(get: { s.orientation }, set: { model.set("layout:orientation", .text($0.rawValue)) }),
                             options: [TileOrientation.auto, .horizontal, .vertical], name: \.title) { OrientationThumbnail(orientation: $0) }
            } header: {
                Text("New windows")
            } footer: {
                Text("Automatic puts tiles side by side on a wide display and above each other on a tall one.").settingsFooter()
            }
            Section("Gaps") {
                GapDiagram(settings: s, screen: model.screen, focus: gapFocus)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Design.Space.s)
                GapField(title: "Between windows, side by side", key: "gaps:inner_horizontal", focus: gapFocus)
                GapField(title: "Between windows, above each other", key: "gaps:inner_vertical", focus: gapFocus)
                GapField(title: "Left edge", key: "gaps:outer_left", focus: gapFocus)
                GapField(title: "Right edge", key: "gaps:outer_right", focus: gapFocus)
                GapField(title: "Bottom edge", key: "gaps:outer_bottom", focus: gapFocus)
                Picker(selection: Binding(get: { s.topGapMode }, set: setTopGapMode)) {
                    Text("Automatic").tag(TopGapMode.auto)
                    Text("Same as other edges").tag(TopGapMode.same)
                    Text("Custom").tag(TopGapMode.custom)
                } label: {
                    Text("Top edge")
                    Text(topEdgeNote).monospacedDigit()
                }
                GapField(title: s.topGapMode == .custom ? "Top gap, built-in display" : "Top gap", key: "gaps:outer_top", focus: gapFocus)
                if s.topGapMode == .custom { GapField(title: "Top gap, other displays", key: "gaps:outer_top_external", focus: gapFocus) }
            }
        }
    }

    /// What the top edge gets: in Automatic, the bar found on the display the window is on.
    private var topEdgeNote: String {
        switch model.settings.topGapMode {
        case .auto: model.screen?.topBar.map { "\($0.owner), \(Int($0.height)) pt. Its height is added to the top gap." }
            ?? "No bar found on this display."
        case .same: "The top gap only, on every display."
        case .custom: "Your own top gap on displays other than the built-in one."
        }
    }

    private func setTopGapMode(_ mode: TopGapMode) {
        // Custom's number is for the displays other than the built-in one: it starts from what they have now,
        // the most of them, so a display with a bar keeps its room.
        let custom = model.screens.filter { !$0.isBuiltIn }.map(model.settings.topGap).max() ?? model.settings.gapOuterTopExternal
        model.set("gaps:outer_top_external", mode == .custom ? .number(custom) : .text(mode.rawValue))
    }
}

extension LayoutMode {
    var title: String {
        switch self {
        case .tiles: "Tiles"
        case .stack: "Stack"
        case .floating: "Floating"
        }
    }
}

extension TileOrientation {
    var title: String {
        switch self {
        case .auto: "Automatic"
        case .horizontal: "Side by side"
        case .vertical: "Above each other"
        }
    }
}

/// Tiles side by side, a fanned stack, or loose overlapping windows.
struct LayoutThumbnail: View {
    let layout: LayoutMode

    var body: some View {
        MiniDesktop(menuBar: 4) {
            GeometryReader { g in
                let w = g.size.width, h = g.size.height, gap: CGFloat = 3, top: CGFloat = 4 + gap
                switch layout {
                case .tiles:
                    let tile = (w - gap * 3) / 2
                    MiniWindow().frame(width: tile, height: h - top - gap).offset(x: gap, y: top)
                    MiniWindow().frame(width: tile, height: h - top - gap).offset(x: gap * 2 + tile, y: top)
                case .stack:
                    ForEach(0 ..< 3) { i in
                        let inset = CGFloat(2 - i) * 3
                        MiniWindow(lights: i == 2).frame(width: w - gap * 2 - inset * 2, height: h - top - gap - inset)
                            .offset(x: gap + inset, y: top + inset * 0.2)
                            .opacity(i == 2 ? 1 : 0.7)
                    }
                case .floating:
                    MiniWindow().frame(width: w * 0.5, height: h * 0.5).offset(x: w * 0.08, y: h * 0.2)
                    MiniWindow().frame(width: w * 0.48, height: h * 0.52).offset(x: w * 0.42, y: h * 0.38)
                }
            }
        }
    }
}

/// Which way tiles split: both ways by display shape, columns, or rows.
struct OrientationThumbnail: View {
    let orientation: TileOrientation

    var body: some View {
        MiniDesktop(menuBar: 4) {
            GeometryReader { g in
                let w = g.size.width, h = g.size.height, gap: CGFloat = 3, top: CGFloat = 4 + gap
                let inner = CGSize(width: w - gap * 2, height: h - top - gap)
                switch orientation {
                case .auto:
                    // A wide display split into columns beside a tall one split into rows.
                    let wide = inner.width * 0.62, tall = inner.width - wide - gap
                    let col = (wide - gap) / 2, row = (inner.height - gap) / 2
                    MiniWindow(lights: false).frame(width: col, height: inner.height).offset(x: gap, y: top)
                    MiniWindow(lights: false).frame(width: col, height: inner.height).offset(x: gap * 2 + col, y: top)
                    MiniWindow(lights: false).frame(width: tall, height: row).offset(x: gap * 2 + wide, y: top)
                    MiniWindow(lights: false).frame(width: tall, height: row).offset(x: gap * 2 + wide, y: top + row + gap)
                case .horizontal:
                    let col = (inner.width - gap * 2) / 3
                    ForEach(0 ..< 3) { i in
                        MiniWindow(lights: false).frame(width: col, height: inner.height).offset(x: gap + CGFloat(i) * (col + gap), y: top)
                    }
                case .vertical:
                    let row = (inner.height - gap * 2) / 3
                    ForEach(0 ..< 3) { i in
                        MiniWindow(lights: false).frame(width: inner.width, height: row).offset(x: gap, y: top + CGFloat(i) * (row + gap))
                    }
                }
            }
        }
    }
}

/// A number of points: a field and a stepper.
struct GapField: View {
    let title: String
    let key: String
    let focus: GapFocus // written, not watched: only the diagram redraws
    @EnvironmentObject var model: SettingsModel
    @FocusState private var editing: Bool

    var body: some View {
        let value = model.number(key)
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, value: value, format: .number.precision(.fractionLength(0)))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .focused($editing)
                    .frame(width: 48)
                Stepper(title, value: value, in: 0 ... 400, step: 2).labelsHidden()
                Text("pt").foregroundStyle(.secondary).frame(width: 16, alignment: .leading)
            }
        }
        // Pointing at a field, or typing in it, lights up its gap in the diagram.
        .onHover { focus.hover(key, $0) }
        .onChange(of: editing) { focus.edit(key, $1) }
    }
}

