import AppKit
import MielCore
import MielRender
import MielSystem
import SwiftUI

/// The zoomed-out canvas as the Appearance pane's settings draw it: the real
/// renderer, made-up windows, the desktop picture of the main display.
@MainActor
final class AppearancePreview: ObservableObject {
    @Published private(set) var image: CGImage?
    let screen: ScreenInfo
    private var state: CanvasState
    private var renderer: Renderer? // made on the first draw, dropped by `release`
    private var frames: SyntheticFrames?
    private var wanted: (settings: MielCore.Settings, dark: Bool)?
    private var drawn: (settings: MielCore.Settings, dark: Bool, accent: RGB?)?
    private var scheduled = false
    private var colors: NSObjectProtocol?

    init() {
        screen = Displays.screens().first ?? ScreenInfo(id: 0, name: "", frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                                        visibleFrame: CGRect(x: 0, y: 32, width: 1512, height: 950), scale: 2)
        let (layout, windows) = syntheticDesk([screen])
        state = CanvasState(screens: [screen], ownPID: getpid(), savedLayout: layout)
        for w in windows { _ = state.send(.system(.windowAppeared(w))) }
        if let first = windows.first { _ = state.send(.system(.windowFocused(first.id))) }
        _ = state.send(.action(.toggleOverview))
        colors = NotificationCenter.default.addObserver(forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule() } // "Automatic" follows the accent color in System Settings
        }
    }

    /// Draws `settings` soon; many calls in a row (a slider moving) draw once.
    func show(_ settings: MielCore.Settings, dark: Bool) {
        wanted = (settings, dark)
        schedule()
    }

    /// Lets go of the renderer and the pictures until the next `show`.
    func release() {
        renderer = nil
        frames = nil
        image = nil
        drawn = nil
    }

    private func schedule() {
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.draw() } }
    }

    private func draw() {
        scheduled = false
        let accent = Controller.systemAccent()
        guard let wanted, drawn.map({ $0.settings != wanted.settings || $0.dark != wanted.dark || $0.accent != accent }) ?? true else { return }
        if renderer == nil {
            renderer = try? Renderer()
            frames = SyntheticFrames(windows: [], scale: 0.75)
            MielSystem.Wallpaper.image(for: screen) { [weak self] image in
                MainActor.assumeIsolated {
                    guard let self, let renderer = self.renderer else { return }
                    renderer.setWallpaper(image, screenID: self.screen.id)
                    self.drawn = nil
                    self.schedule()
                }
            }
        }
        guard let renderer, let frames else { return }
        drawn = (wanted.settings, wanted.dark, accent)
        state.settings = wanted.settings
        state.systemAccent = accent
        state.systemDark = wanted.dark
        state.liquidGlassAvailable = Controller.liquidGlassAvailable
        var t = state.now
        for _ in 0 ..< 600 where !state.animator.isSettled { // a new zoomed-out level flies there first
            t += 1.0 / 60
            _ = state.send(.tick(t))
        }
        let scene = state.scene(for: screen, time: t)
        frames.update(scene.windows)
        let width = 960.0 // px: the pane shows it at about half that, on a Retina display
        image = renderer.renderImage(scene, frames: frames, pixelSize: CGSize(width: width, height: (width * screen.frame.height / screen.frame.width).rounded()))
    }
}

struct AppearancePreviewView: View {
    let settings: MielCore.Settings
    let dark: Bool
    @ObservedObject var preview: AppearancePreview

    var body: some View {
        let aspect = preview.screen.frame.width / max(preview.screen.frame.height, 1)
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black.opacity(0.85))
            if let image = preview.image {
                Image(decorative: image, scale: 2).resizable().interpolation(.high)
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .frame(maxWidth: 400)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .onAppear { preview.show(settings, dark: dark) }
        .onChange(of: settings) { preview.show(settings, dark: dark) }
        .onChange(of: dark) { preview.show(settings, dark: dark) }
        .accessibilityLabel("Preview of the zoomed-out canvas")
    }
}
