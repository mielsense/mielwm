import AppKit
import MielCore
import MielSystem
import SwiftUI

/// Explains the two permissions and opens the right System Settings pages.
/// Polls until Accessibility is granted; Screen Recording only applies after
/// a restart, so it offers one. Closing the window ends it too, so the app
/// never waits on a window that is gone.
@MainActor
final class Onboarding: NSObject, NSWindowDelegate {
    let window: NSWindow
    let model: OnboardingModel
    private var timer: Timer?
    private let done: () -> Void

    init(note: String?, done: @escaping () -> Void) {
        self.done = done
        model = OnboardingModel(note: note)
        window = Onboarding.makeWindow(model)
        super.init()
        model.finish = { [weak self] in self?.finish() }
        window.delegate = self
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
    }

    func show() {
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        finish()
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

/// What the welcome window shows: which permissions are allowed, and the import note.
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

/// The welcome window's content.
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: 0) {
            IconTile(image: appIcon(), size: 80)
                .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
            Text("Welcome to mielwm").font(Design.headerTitle).padding(.top, Design.Space.m)
            Text("Your windows on one endless canvas, tiled in workspaces. mielwm needs two permissions to work.")
                .font(Design.row)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Design.Space.xs)
            VStack(spacing: 0) {
                PermissionRow(title: "Accessibility", detail: "To move and focus windows, and to hear your shortcuts.",
                              symbol: "accessibility", tint: Design.Tint.blue, granted: model.accessibility, open: model.openAccessibility)
                Divider().padding(.leading, Design.Space.m + Design.Tile.row + Design.Space.s + 2)
                PermissionRow(title: "Screen Recording", detail: "To show live pictures of your windows when you zoom out.",
                              symbol: "rectangle.inset.filled.badge.record", tint: Design.Tint.red, granted: model.recording, open: model.openRecording)
            }
            .background(RoundedRectangle(cornerRadius: Design.Radius.group, style: .continuous).fill(Design.groupFill))
            .overlay(RoundedRectangle(cornerRadius: Design.Radius.group, style: .continuous).strokeBorder(Design.edge(contrast)))
            .padding(.top, Design.Space.xxl)
            VStack(alignment: .leading, spacing: Design.Space.s) {
                if !model.recording {
                    Text("macOS turns Screen Recording on after mielwm restarts, and may ask again now and then. Without it, windows show as plain cards when you zoom out.")
                }
                if let note = model.note {
                    Label { Text(note) } icon: { Image(systemName: "square.and.arrow.down") }
                }
            }
            .font(Design.secondary)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Design.Space.m)
            .padding(.top, Design.Space.s)
            HStack(spacing: Design.Space.m) {
                Spacer()
                if !model.recording { Button("Restart mielwm", action: model.restart) }
                Button("Continue") { model.finish() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.accessibility)
            }
            .controlSize(.large)
            .padding(.top, Design.Space.xl)
        }
        .padding(.horizontal, Design.Space.xxl + Design.Space.s)
        .padding(.top, Design.Space.xxl + Design.Space.m)
        .padding(.bottom, Design.Space.xxl)
        .frame(width: 520)
    }
}

/// A permission as Privacy & Security lists one: its icon, what it is for, and whether it is allowed.
struct PermissionRow: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    let granted: Bool
    let open: () -> Void

    var body: some View {
        HStack(spacing: Design.Space.s + 2) {
            IconTile(symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Design.row)
                Text(detail).font(Design.secondary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Design.Space.s)
            if granted {
                StatusBadge(text: "Allowed", symbol: "checkmark.circle.fill", tint: .green)
                    .accessibilityLabel("\(title) is allowed")
            } else {
                Button("Allow…", action: open)
                    .help("Opens Privacy & Security in System Settings")
            }
        }
        .padding(.horizontal, Design.Space.m)
        .padding(.vertical, Design.Space.s + 2)
    }
}
