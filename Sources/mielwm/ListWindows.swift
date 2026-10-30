import AppKit
import MielCore
import MielSystem
import ScreenCaptureKit

@MainActor
func listWindows(json: Bool, fps: Bool, pid: Int32?) {
    _ = NSApplication.shared
    let screens = Displays.screens()
    let (windows, _) = readWindows(pid: pid)
    var onScreen: [UInt32: Bool] = [:]
    var done = false
    SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { content, _ in
        let pairs = (content?.windows ?? []).map { ($0.windowID, $0.isOnScreen) }
        DispatchQueue.main.async {
            onScreen = Dictionary(pairs, uniquingKeysWith: { a, _ in a })
            done = true
        }
    }
    spin(3) { done }

    // Frames per second each visible window's stream delivers, as the overview would see it.
    var rates: [WindowID: Double] = [:]
    if fps {
        let capture = CaptureManager()
        let visible = windows.filter { !isHiddenFrame($0.frame, screens: screens) && !$0.isMinimized }
        capture.setRate(.overview)
        for w in visible { capture.warm([w.id], maxPixelSize: w.frame.size) }
        spin(0.8)
        let start = Dictionary(visible.map { ($0.id, capture.generation(for: $0.id)) }, uniquingKeysWith: { a, _ in a })
        spin(2)
        for w in visible { rates[w.id] = Double(capture.generation(for: w.id) - start[w.id]!) / 2 }
        capture.stop(dropFrames: true)
    }

    if json {
        struct Row: Encodable {
            var id: String, pid: Int32, app: String, title: String, frame: [Double]
            var visible: Bool, managed: Bool, minimized: Bool, sckOnScreen: Bool?, fps: Double?
        }
        let rows = windows.map { w in
            Row(id: w.id.description, pid: w.id.pid, app: w.appName, title: w.title,
                frame: [w.frame.minX, w.frame.minY, w.frame.width, w.frame.height],
                visible: !isHiddenFrame(w.frame, screens: screens), managed: w.isManageable, minimized: w.isMinimized,
                sckOnScreen: onScreen[w.id.number], fps: rates[w.id])
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: (try? encoder.encode(rows)) ?? Data(), as: UTF8.self))
        return
    }
    for s in screens {
        print("screen \(s.id) \(s.name): frame \(fmt(s.frame)) visible \(fmt(s.visibleFrame)) @\(Int(s.scale))x")
    }
    for w in windows {
        var flags = [isHiddenFrame(w.frame, screens: screens) ? "hidden" : "visible"]
        if !w.isStandard { flags.append("not-standard") }
        if !w.isMovable { flags.append("not-movable") }
        if w.isMinimized { flags.append("minimized") }
        if onScreen[w.id.number] == false { flags.append("sck-offscreen") }
        if let r = rates[w.id] { flags.append(String(format: "%.0ffps", r)) }
        let title = w.title.isEmpty ? "" : " \"\(w.title)\""
        print("\(w.id)\t\(w.appName)\(title)\t\(fmt(w.frame))\t\(flags.joined(separator: " "))")
    }
}

func fmt(_ r: CGRect) -> String {
    String(format: "%.0f,%.0f %.0fx%.0f", r.minX, r.minY, r.width, r.height)
}
