import AppKit
import MielCore
import SwiftUI

/// Settings > Trackpad & mouse.
struct TrackpadPane: View {
    @EnvironmentObject var model: SettingsModel

    /// Modifier sets offered for moving windows; another one from config.json shows too.
    private static let moveModifiers = ["ctrl+opt", "ctrl+cmd", "opt+cmd", "ctrl+opt+cmd"]

    var body: some View {
        let s = model.settings
        let current = String(KeyChord(modifiers: s.moveModifiers, key: "a").description.dropLast(2)) // "ctrl+opt"
        Form {
            Section { PaneHeader(pane: .trackpad) }
            Section {
                Toggle(isOn: model.flag("input:swipe_workspaces")) {
                    Text("Swipe between workspaces")
                    Text("Three fingers left or right on the trackpad go to the next or previous workspace, with a click you can feel.")
                }
                if s.swipeWorkspaces, systemThreeFingerSwipe() {
                    LabeledContent {
                        Button("Open Trackpad settings…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!)
                        }
                    } label: {
                        Label("macOS swipes with three fingers too", systemImage: "exclamationmark.triangle.fill")
                            .symbolRenderingMode(.multicolor)
                        Text("Its swipe between full-screen apps bounces the screen as you swipe. In More Gestures, set it to four fingers.")
                    }
                }
            } header: {
                Text("Trackpad")
            }
            Section {
                Picker(selection: Binding(get: { current }, set: { model.set("input:move_modifier", .text($0)) })) {
                    ForEach(Self.moveModifiers.contains(current) ? Self.moveModifiers : Self.moveModifiers + [current], id: \.self) { key in
                        Text(KeyChord.modifiers(key)?.symbols ?? key).tag(key)
                    }
                } label: {
                    Text("Move and resize windows")
                    Text("Hold these keys and drag anywhere in a window to move it, or drag with the right button to resize it.")
                }
            } header: {
                Text("Windows")
            }
            Section {
                Toggle(isOn: model.flag("navigator:pointer")) {
                    Text("Use the pointer in the overview")
                    Text("Click a window to go to it, drag to move windows or the canvas, scroll to zoom.")
                }
                LabeledSlider("Panning speed", value: doubling("input:pan_sensitivity"), in: -2 ... 2, format: doublingText)
                LabeledSlider("Zoom speed", value: doubling("input:scroll_factor"), in: -2 ... 2, format: doublingText)
            } header: {
                Text("Pointer and scrolling")
            } footer: {
                Text("Panning speed is for dragging the canvas, with the middle button or in the overview. Zoom speed is for the scroll wheel, in the overview or with the keys above held.").settingsFooter()
            }
        }
    }

    /// A setting on a doubling scale: 1× in the middle, from 4× slower to 4× faster.
    private func doubling(_ key: String) -> Binding<Double> {
        let value = model.number(key)
        return Binding(get: { log2(max(0.01, value.wrappedValue)) }, set: { value.wrappedValue = pow(2, $0) })
    }
}

/// macOS's own three-finger swipe between full-screen apps (Trackpad > More Gestures), built in or Magic Trackpad.
func systemThreeFingerSwipe() -> Bool {
    ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"].contains { domain in
        CFPreferencesAppSynchronize(domain as CFString)
        return (CFPreferencesCopyAppValue("TrackpadThreeFingerHorizSwipeGesture" as CFString, domain as CFString) as? Int) == 2
    }
}
