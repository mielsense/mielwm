import AppKit
import MielCore
import ScreenCaptureKit

/// The desktop pictures the overview draws behind the canvas.
public enum Wallpaper {
    /// The desktop picture of `screen`, decoded (off the main thread) at no
    /// more than the size that covers the screen: a 6K picture would
    /// otherwise stay decoded in full. Dynamic (.heic) and other wallpapers
    /// that are not a plain image are captured from the system's wallpaper
    /// window instead. Completion on the main queue, nil if both fail.
    public static func image(for screen: ScreenInfo, completion: @escaping @MainActor @Sendable (CGImage?) -> Void) {
        let nsScreen = NSScreen.screens.first { $0.displayID == screen.id }
        guard let url = nsScreen.flatMap(NSWorkspace.shared.desktopImageURL(for:)), url.pathExtension.lowercased() != "heic" else {
            return captureWallpaperWindow(screen, completion: completion)
        }
        DispatchQueue.global(qos: .utility).async {
            let image = decode(url, covering: CGSize(width: screen.frame.width * screen.scale, height: screen.frame.height * screen.scale))
            DispatchQueue.main.async { image.map(completion) ?? captureWallpaperWindow(screen, completion: completion) }
        }
    }

    /// The picture at `url`, scaled down (never up) to the smallest size that still covers `pixels`.
    static func decode(_ url: URL, covering pixels: CGSize) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              var width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              var height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue, width > 0, height > 0
        else { return nil }
        if let o = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue, o >= 5 { swap(&width, &height) } // stored rotated
        let fill = max(pixels.width / width, pixels.height / height)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: (max(width, height) * min(fill, 1)).rounded(.up),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The window the system draws the wallpaper in: WindowManager's
    /// "Wallpaper" since macOS 14, the Dock's "Desktop Picture" before.
    static func captureWallpaperWindow(_ screen: ScreenInfo, completion: @escaping @MainActor @Sendable (CGImage?) -> Void) {
        let done = { @Sendable (image: CGImage?) in DispatchQueue.main.async { completion(image) } }
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, _ in
            let owners = ["com.apple.WindowManager", "com.apple.dock"]
            guard let window = content?.windows.first(where: { w in
                owners.contains(w.owningApplication?.bundleIdentifier ?? "")
                    && (w.title?.hasPrefix("Wallpaper") == true || w.title?.hasPrefix("Desktop Picture") == true)
                    && screen.frame.contains(w.frame.center)
            }) else { return done(nil) }
            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width * screen.scale)
            config.height = Int(screen.frame.height * screen.scale)
            config.showsCursor = false
            SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window),
                                             configuration: config) { image, _ in done(image) }
        }
    }
}
