import SwiftUI

/// A small drawn desktop for thumbnails and diagrams: a soft wallpaper, a menu
/// bar strip, and whatever is placed on it, in a rounded display shape.
struct MiniDesktop<Content: View>: View {
    var menuBar: CGFloat = 5 // the strip's height; 0 for none
    var radius: CGFloat = Design.Radius.thumbnail
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: Self.wallpaper(dark: scheme == .dark), startPoint: .topLeading, endPoint: .bottomTrailing)
            content
            if menuBar > 0 {
                Rectangle().fill(.white.opacity(scheme == .dark ? 0.12 : 0.45)).frame(height: menuBar)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// A calm blue to violet, lighter in light mode.
    static func wallpaper(dark: Bool) -> [Color] {
        dark ? [Color(red: 0.16, green: 0.24, blue: 0.42), Color(red: 0.3, green: 0.2, blue: 0.4)]
            : [Color(red: 0.6, green: 0.74, blue: 0.96), Color(red: 0.8, green: 0.68, blue: 0.93)]
    }
}

/// A window on a MiniDesktop: a light card with tiny traffic lights and a soft shadow.
struct MiniWindow: View {
    var highlighted = false
    var lights = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { g in
            let r = min(4, min(g.size.width, g.size.height) * 0.12)
            let dot = max(2, min(4, g.size.width * 0.06))
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(scheme == .dark ? Color(white: 0.24) : .white)
                .shadow(color: .black.opacity(0.18), radius: 1.5, y: 0.5)
                .overlay {
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .strokeBorder(highlighted ? Color.accentColor : .clear, lineWidth: 1.5)
                }
                .overlay(alignment: .topLeading) {
                    if lights, g.size.width > dot * 6, g.size.height > dot * 3 {
                        HStack(spacing: dot * 0.5) {
                            ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.85)).frame(width: dot, height: dot) }
                        }
                        .padding(dot * 0.9)
                    }
                }
        }
    }
}
