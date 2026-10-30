import AppKit
import MielCore
import SwiftUI

// What the overview's panels are made of: Liquid glass, frosted or solid, after `Design.ChromeMaterial`.

extension View {
    /// Liquid glass, frosted, or solid with Reduce Transparency; outlined with Increase Contrast.
    /// `behindWindow`: what to blur is the desktop behind the overlay, not the canvas inside it (frosted only).
    func chromeMaterial<S: InsettableShape>(_ shape: S, look: Look, behindWindow: Bool = false) -> some View {
        modifier(ChromeSurface(shape: shape, look: look, behindWindow: behindWindow))
    }
}

/// Draws a panel in the material `Design.ChromeMaterial` picks.
private struct ChromeSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let look: Look
    let behindWindow: Bool
    @Environment(\.chromeStill) private var still

    func body(content: Content) -> some View {
        let material = still ? .solid : Design.ChromeMaterial.current(look) // glass and frosted draw only on screen
        Group {
            switch material {
            case .solid:
                content.background(shape.fill(Color(nsColor: .windowBackgroundColor)))
                    .shadow(color: .black.opacity(look.dark ? 0.4 : 0.2), radius: 14, y: 4)
            case .glass:
                if #available(macOS 26, *) { content.glassEffect(.regular, in: shape) }
            case .hud:
                content.background(Frosted(behindWindow: behindWindow).clipShape(shape))
                    .shadow(color: .black.opacity(look.dark ? 0.4 : 0.2), radius: 14, y: 4)
            }
        }
        .overlay { if look.increaseContrast { shape.strokeBorder(.primary.opacity(0.6), lineWidth: 1) } }
        .environment(\.keyCapFill, Design.KeyCap.fill(on: material))
    }
}

/// The frosted HUD material of macOS before 26.
private struct Frosted: NSViewRepresentable {
    let behindWindow: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.blendingMode = behindWindow ? .behindWindow : .withinWindow
    }
}
