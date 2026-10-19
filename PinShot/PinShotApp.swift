import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only one PinShot at a time: quit any older copy (e.g. after an update or restart)
        let me = NSRunningApplication.current
        for other in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        where other != me {
            other.terminate()
        }
        _ = CaptureStore.shared
        HotKeyCenter.shared.start(capture: { CaptureController.shared.startCapture(mode: .pin) },
                                  text: { CaptureController.shared.startCapture(mode: .text) })
    }
}

@main
struct PinShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var pins = PinManager.shared

    var body: some Scene {
        MenuBarExtra("PinShot", systemImage: "pin") {
            Button("Capture Area or Window  \(settings.hotKeyDisplay)") { CaptureController.shared.startCapture(mode: .pin) }
            Button("Capture Text  \(settings.textHotKeyDisplay)") { CaptureController.shared.startCapture(mode: .text) }
            Button("Capture Full Screen") { CaptureController.shared.captureFullScreen() }
            Divider()
            Button("Show Library…") { LibraryWindowController.shared.show() }
                .keyboardShortcut("l")
            if !pins.pins.isEmpty {
                Button("Close All Pins (\(pins.pins.count))") { PinManager.shared.closeAll() }
            }
            if pins.hasLockedPins {
                Button("Unlock Click-Through Pins") { PinManager.shared.unlockAll() }
            }
            Divider()
            Button("Settings…") { SettingsWindowController.shared.show() }
                .keyboardShortcut(",")
            Button("Quit PinShot") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
