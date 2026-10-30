import MielCore
import SwiftUI

/// A slider with its value; changes apply as it moves and are saved when it is let go.
struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String
    @EnvironmentObject var model: SettingsModel

    init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, format: @escaping (Double) -> String) {
        self.title = title
        _value = value
        self.range = range
        self.format = format
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Slider(value: $value, in: range) { Text(title) } onEditingChanged: { if !$0 { model.flush() } }
                    .labelsHidden()
                    .controlSize(.small)
                Text(format(value)).monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
            }
            .frame(width: 220)
        }
    }
}

private let footerIndent: CGFloat = ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)) ? 0 : 10

extension Text {
    /// Indented like the section titles and row labels, so all text starts on one edge. macOS 26 indents footers itself.
    func settingsFooter() -> some View {
        font(Design.secondary).foregroundStyle(.secondary).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, footerIndent)
    }
}

/// "1×", "2×", "0.5×".
func doublingText(_ exponent: Double) -> String {
    String(format: pow(2, exponent) < 0.95 ? "%.2g×" : "%.1f×", pow(2, exponent)).replacingOccurrences(of: ".0×", with: "×")
}

/// View state that changes as the pointer moves, kept out of SettingsModel so it redraws only
/// the views that show it. This SDK declares @State as a macro and the Command Line Tools lack
/// SwiftUI's macro plugin, so it won't compile there; @StateObject and @FocusState are plain property wrappers.
final class Hover: ObservableObject {
    @Published var on = false
}

/// The gap field being pointed at or typed in, lit up in the gaps diagram.
final class GapFocus: ObservableObject {
    @Published var key: String?
    var editing: String? // the field being typed in, lit again when the pointer leaves another

    func hover(_ field: String, _ inside: Bool) {
        if inside { key = field } else if key == field { key = editing }
    }

    func edit(_ field: String, _ now: Bool) {
        if now { editing = field } else if editing == field { editing = nil }
        key = now ? field : (key == field ? editing : key)
    }
}
