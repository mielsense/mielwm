import MielCore
import SwiftUI

/// A small desktop with three tiled windows, drawn with the gaps as they are
/// set: half size, so the gaps read at a glance. Thin accent markers measure
/// each gap; the one being edited is brighter and shows its value.
struct GapDiagram: View {
    let settings: MielCore.Settings
    let screen: ScreenInfo? // the top gap and status bar on this display
    @ObservedObject var focus: GapFocus // the gaps:… key being pointed at or edited
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let size = CGSize(width: 248, height: 155)
    private static let k = 0.5, menuBar: CGFloat = 7

    private var topGap: Double { screen.map(settings.topGap) ?? settings.gapOuterTop }

    var body: some View {
        let s = settings, k = Self.k, size = Self.size
        let bar = s.topGapMode == .auto ? (screen?.topBar?.height ?? 0) * k : 0
        let top = Self.menuBar + topGap * k
        let area = CGRect(x: s.gapOuterLeft * k, y: top, width: size.width - (s.gapOuterLeft + s.gapOuterRight) * k,
                          height: size.height - top - s.gapOuterBottom * k)
        let tileWidth = max(4, (area.width - s.gapInnerHorizontal * k) / 2)
        let rightHeight = max(4, (area.height - s.gapInnerVertical * k) / 2)
        let left = CGRect(x: area.minX, y: area.minY, width: tileWidth, height: max(4, area.height))
        let upper = CGRect(x: area.maxX - tileWidth, y: area.minY, width: tileWidth, height: rightHeight)
        let lower = CGRect(x: area.maxX - tileWidth, y: area.maxY - rightHeight, width: tileWidth, height: rightHeight)
        let markers: [Marker] = [
            Marker(keys: ["gaps:outer_left"], from: CGPoint(x: 0, y: left.midY), to: CGPoint(x: left.minX, y: left.midY), value: s.gapOuterLeft),
            Marker(keys: ["gaps:outer_right"], from: CGPoint(x: upper.maxX, y: upper.midY), to: CGPoint(x: size.width, y: upper.midY), value: s.gapOuterRight),
            Marker(keys: ["gaps:outer_bottom"], from: CGPoint(x: left.midX, y: left.maxY), to: CGPoint(x: left.midX, y: size.height), value: s.gapOuterBottom),
            Marker(keys: ["gaps:outer_top", "gaps:outer_top_external"], from: CGPoint(x: left.midX, y: Self.menuBar + bar),
                   to: CGPoint(x: left.midX, y: left.minY), value: topGap - bar / k),
            Marker(keys: ["gaps:inner_horizontal"], from: CGPoint(x: left.maxX, y: lower.midY), to: CGPoint(x: lower.minX, y: lower.midY), value: s.gapInnerHorizontal),
            Marker(keys: ["gaps:inner_vertical"], from: CGPoint(x: upper.midX, y: upper.maxY), to: CGPoint(x: upper.midX, y: lower.minY), value: s.gapInnerVertical),
        ]
        MiniDesktop(menuBar: Self.menuBar, radius: 10) {
            ZStack(alignment: .topLeading) {
                if bar > 0 { // the status bar the gap makes room for
                    Rectangle().fill(.black.opacity(0.22)).frame(width: size.width, height: bar).offset(y: Self.menuBar)
                }
                ForEach(Array([left, upper, lower].enumerated()), id: \.offset) { _, tile in
                    MiniWindow().frame(width: tile.width, height: tile.height).offset(x: tile.minX, y: tile.minY)
                }
                ForEach(markers, id: \.keys) { marker in
                    MarkerView(marker: marker, focused: focus.key.map(marker.keys.contains) ?? false,
                               glass: s.look.glass)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
        .frame(width: size.width, height: size.height)
        .animation(Design.follow(reduceMotion: reduceMotion), value: [area.minX, area.minY, area.width, area.height, tileWidth, rightHeight, bar])
        .animation(.easeOut(duration: 0.12), value: focus.key)
        .accessibilityElement()
        .accessibilityLabel("A display with three windows and the gaps around them, \(Int(topGap)) pt at the top")
    }

    /// One gap the diagram labels: the settings it shows and where its line runs.
    struct Marker {
        let keys: [String]
        let from: CGPoint
        let to: CGPoint
        let value: Double
    }

    /// A dimension line with end ticks; the edited one is bright and labeled.
    private struct MarkerView: View {
        let marker: Marker
        let focused: Bool
        let glass: GlassStyle

        var body: some View {
            let horizontal = marker.from.y == marker.to.y
            let length = horizontal ? marker.to.x - marker.from.x : marker.to.y - marker.from.y
            if length >= 3 {
                ZStack {
                    Path { p in
                        let tick: CGFloat = 2.5
                        p.move(to: marker.from)
                        p.addLine(to: marker.to)
                        for end in [marker.from, marker.to] {
                            p.move(to: horizontal ? CGPoint(x: end.x, y: end.y - tick) : CGPoint(x: end.x - tick, y: end.y))
                            p.addLine(to: horizontal ? CGPoint(x: end.x, y: end.y + tick) : CGPoint(x: end.x + tick, y: end.y))
                        }
                    }
                    .stroke(Color.accentColor.opacity(focused ? 1 : 0.55), lineWidth: focused ? 1.5 : 1)
                    if focused {
                        Text("\(Int(marker.value.rounded())) pt")
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .glassSurface(glass, in: Capsule())
                            .position(x: (marker.from.x + marker.to.x) / 2 + (horizontal ? 0 : 22), y: (marker.from.y + marker.to.y) / 2 + (horizontal ? -10 : 0))
                    }
                }
            }
        }
    }
}
