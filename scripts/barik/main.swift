import AppKit

// Barik's side of scripts/barik-test.sh, built from Barik's own code in this folder.
//
//   barik-check <aerospace>                       what Barik would show, as JSON
//   barik-check <aerospace> focus-window <id>     a click on a window
//   barik-check <aerospace> focus-space <id>      a click on a workspace

let provider = AerospaceSpacesProvider()
let args = CommandLine.arguments
switch args.count > 3 ? args[2] : "" {
case "focus-window": provider.focusWindow(windowId: args[3])
case "focus-space": provider.focusSpace(spaceId: args[3], needWindowFocus: false)
default:
    // Barik's detection, from SpacesViewModel.init: a running app named AeroSpace, any case.
    let named = NSWorkspace.shared.runningApplications.filter { $0.localizedName?.lowercased() == "aerospace" }
    let spaces = provider.getSpacesWithWindows()
    let out: [String: Any] = [
        "detected": !named.isEmpty,
        "bundleIDs": named.compactMap(\.bundleIdentifier),
        "spaces": (spaces ?? []).sorted { $0.id < $1.id }.map { space in
            ["id": space.id, "focused": space.isFocused,
             "windows": space.windows.map { ["id": $0.id, "title": $0.title, "app": $0.appName ?? "", "focused": $0.isFocused] }]
        },
    ]
    print(String(decoding: try! JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]), as: UTF8.self))
}
