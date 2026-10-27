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

extension Text {
    func settingsFooter() -> some View {
        font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
    }
}
