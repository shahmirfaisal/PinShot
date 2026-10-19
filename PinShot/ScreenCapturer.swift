import AppKit
import ScreenCaptureKit

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

/// A window that can be picked in the capture overlay.
struct PickableWindow {
    let window: SCWindow
    /// Frame in AppKit global coordinates (bottom-left origin).
    let frame: NSRect
}

enum ScreenCapturer {
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    /// Takes a full-resolution picture of one screen (without the cursor).
    static func capture(screen: NSScreen, content: SCShareableContent) async throws -> CGImage {
        guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
            throw CaptureError.noDisplay
        }
        let ownApp = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: pinWindows(in: content))
        let config = SCStreamConfiguration()
        let scale = screen.backingScaleFactor
        config.width = Int(screen.frame.width * scale)
        config.height = Int(screen.frame.height * scale)
        config.showsCursor = false
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Captures a single window on its own, without whatever overlaps it.
    static func capture(window: SCWindow, scale: CGFloat) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.showsCursor = false
        config.captureResolution = .best
        config.ignoreShadowsSingleWindow = true
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Normal app windows currently on screen, front-most first.
    static func pickableWindows(in content: SCShareableContent) -> [PickableWindow] {
        let ownBundle = Bundle.main.bundleIdentifier
        let candidates = content.windows.filter { w in
            w.isOnScreen && w.windowLayer == 0 &&
            w.frame.width > 40 && w.frame.height > 40 &&
            w.owningApplication?.bundleIdentifier != ownBundle
        }
        // CGWindowList returns windows in front-to-back order, with reliable on-screen bounds
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        var rank: [CGWindowID: Int] = [:]
        var bounds: [CGWindowID: CGRect] = [:]
        for (index, entry) in info.enumerated() {
            guard let id = entry[kCGWindowNumber as String] as? CGWindowID else { continue }
            rank[id] = index
            if let dict = entry[kCGWindowBounds as String] as? NSDictionary,
               let rect = CGRect(dictionaryRepresentation: dict) {
                bounds[id] = rect
            }
        }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return candidates
            .sorted { (rank[$0.windowID] ?? .max) < (rank[$1.windowID] ?? .max) }
            .map { w in
                let f = bounds[w.windowID] ?? w.frame // top-left origin, global points
                return PickableWindow(window: w,
                                      frame: NSRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height))
            }
    }

    /// Pinned shots stay visible in captures (so you can capture a pin), but not other PinShot UI.
    private static func pinWindows(in content: SCShareableContent) -> [SCWindow] {
        let pinIDs = Set(PinManager.shared.pins.map { CGWindowID($0.panel.windowNumber) })
        return content.windows.filter { pinIDs.contains($0.windowID) }
    }

    enum CaptureError: Error { case noDisplay }
}
