import AppKit
import MielCore
import MielSystem
import SwiftUI

/// Explains the two permissions and opens the right System Settings pages.
/// Polls until Accessibility is granted; Screen Recording only applies after
/// a restart, so it offers one.
@MainActor
final class Onboarding: NSObject {
    private let window: NSWindow
    private let model: OnboardingModel
    private var timer: Timer?
    private let done: () -> Void

    init(note: String?, done: @escaping () -> Void) {
        self.done = done
        model = OnboardingModel(note: note)
        window = Onboarding.makeWindow(model)
        super.init()
        model.finish = { [weak self] in self?.finish() }
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
    }

    /// A title-less window, as Apple's welcome windows are.
    static func makeWindow(_ model: OnboardingModel) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: OnboardingView(model: model)))
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Welcome to mielwm"
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        return window
    }

    private func refresh() {
        model.refresh()
        if model.accessibility, model.recording { finish() }
    }

    private func finish() {
        guard timer != nil else { return }
        timer?.invalidate()
        timer = nil
        window.close()
        done()
    }
}

@MainActor
final class OnboardingModel: ObservableObject {
    @Published var accessibility = Permissions.accessibility()
    @Published var recording = Permissions.screenRecording()
    let note: String? // what was imported from AeroSpace, told once
    var finish: () -> Void = {}

    init(note: String?) {
        self.note = note
    }

    func refresh() {
        let ax = Permissions.accessibility(), rec = Permissions.screenRecording()
        if ax != accessibility { accessibility = ax }
        if rec != recording { recording = rec }
    }

    func openAccessibility() {
        _ = Permissions.accessibility(prompt: true)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func openRecording() {
        _ = Permissions.screenRecording(request: true)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    func restart() {
        // After this process is gone; a bundle goes through `open` so it keeps its own permissions.
        let bundle = Bundle.main.bundlePath.hasSuffix(".app")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", bundle ? "sleep 1; open -n \"$0\"" : "sleep 1; exec \"$0\"",
                       bundle ? Bundle.main.bundlePath : Bundle.main.executablePath ?? ""]
        try? p.run()
        NSApp.terminate(nil)
    }
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: appIcon()).resizable().frame(width: 88, height: 88).accessibilityHidden(true)
            Text("Welcome to mielwm").font(.system(size: 24, weight: .semibold)).padding(.top, 12)
            Text("Your windows on one endless canvas, tiled in workspaces.")
                .font(.system(size: 13)).foregroundStyle(.secondary).padding(.top, 4)
            VStack(spacing: 0) {
                PermissionRow(title: "Accessibility", detail: "To move and focus windows, and to hear your shortcuts.",
                              symbol: "accessibility", color: Color(nsColor: .systemBlue), granted: model.accessibility, open: model.openAccessibility)
                Divider().padding(.leading, 52)
                PermissionRow(title: "Screen Recording", detail: "To show live pictures of your windows when you zoom out.",
                              symbol: "rectangle.inset.filled.badge.record", color: Color(nsColor: .systemRed), granted: model.recording, open: model.openRecording)
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .quaternarySystemFill)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(nsColor: .separatorColor).opacity(0.5)))
            .padding(.top, 24)
            VStack(alignment: .leading, spacing: 8) {
                if !model.recording {
                    Text("macOS turns Screen Recording on after mielwm restarts, and may ask again now and then. Without it, windows show as plain cards when you zoom out.")
                }
                if let note = model.note {
                    Label { Text(note) } icon: { Image(systemName: "square.and.arrow.down") }
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
            HStack {
                Spacer()
                if !model.recording { Button("Restart mielwm", action: model.restart) }
                Button("Continue") { model.finish() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.accessibility)
            }
            .controlSize(.large)
            .padding(.top, 20)
        }
        .padding(.horizontal, 32)
        .padding(.top, 36)
        .padding(.bottom, 24)
        .frame(width: 520)
    }
}

struct PermissionRow: View {
    let title: String
    let detail: String
    let symbol: String
    let color: Color
    let granted: Bool
    let open: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color.gradient))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if granted {
                Label { Text("Allowed").foregroundStyle(.secondary) } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    .accessibilityLabel("\(title) is allowed")
            } else {
                Button("Open System Settings", action: open)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

/// The one-time notice after a first-launch import from AeroSpace.
func aeroSpaceImportNote(_ found: AeroSpaceImport) -> String {
    var parts: [String] = []
    if !found.gaps.isEmpty { parts.append("gaps") }
    if found.layout != nil || found.orientation != nil { parts.append("layout") }
    if !found.workspaceRules.isEmpty { parts.append("\(found.workspaceRules.count) workspace rules") }
    if !found.floatingApps.isEmpty { parts.append("\(found.floatingApps.count) floating apps") }
    let list = parts.count > 1 ? parts.dropLast().joined(separator: ", ") + " and " + parts.last! : parts.joined()
    return "mielwm took your \(list) from AeroSpace's config. Change them any time in Settings > Layout & workspaces."
}
