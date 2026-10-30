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
/// the views that show it. (The Command Line Tools can't expand @State; @StateObject works.)
final class Hover: ObservableObject {
    @Published var on = false
}

/// The gap field being pointed at or typed in, lit up in the gaps diagram.
final class GapFocus: ObservableObject {
    @Published var key: String?
}
