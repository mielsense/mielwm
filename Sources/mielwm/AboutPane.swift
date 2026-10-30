import AppKit
import SwiftUI

/// Settings > About: the version, and links to the website, the docs and the source.
struct AboutPane: View {
    private static let links: [(title: String, symbol: String, tint: Color, url: String)] = [
        ("Website", "globe", Design.Tint.blue, "https://wm.miel.my"),
        ("Documentation", "book.fill", Design.Tint.orange, "https://wm.miel.my/docs"),
        ("Changelog", "list.bullet", Design.Tint.gray, "https://wm.miel.my/docs/changelog"),
        ("Source code", "chevron.left.forwardslash.chevron.right", Design.Tint.graphite, "https://github.com/mielsense/mielwm"),
    ]

    var body: some View {
        Form {
            Section { PaneHeader(pane: .about) }
            Section {
                LabeledContent("Version") { Text(appVersion).textSelection(.enabled) }
            }
            Section {
                ForEach(Self.links, id: \.title) { link in
                    LinkRow(title: link.title, icon: IconTile(link.symbol, tint: link.tint), url: URL(string: link.url)!)
                }
            }
            Section {
                LinkRow(title: "License", subtitle: "MIT License, with code from Phantomat under the BSD 3-Clause License.",
                        icon: IconTile("doc.text.fill", tint: Design.Tint.gray), url: URL(string: "https://github.com/mielsense/mielwm/blob/main/NOTICE")!)
            }
        }
    }
}

/// A row that opens a web page, with the arrow System Settings puts on links.
struct LinkRow: View {
    let title: String
    var subtitle: String?
    let icon: IconTile
    let url: URL

    var body: some View {
        Link(destination: url) {
            SettingsRow(title, subtitle: subtitle, icon: icon) {
                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .foregroundStyle(.primary) // a row, not blue link text
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens \(url.host() ?? "the page") in your browser")
    }
}
