import Foundation
import Combine
import Carbon.HIToolbox

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    // Global capture shortcut (Carbon key code + modifiers), default ⇧⌘2
    @Published var hotKeyCode: Int { didSet { defaults.set(hotKeyCode, forKey: "hotKeyCode") } }
    @Published var hotKeyModifiers: Int { didSet { defaults.set(hotKeyModifiers, forKey: "hotKeyModifiers") } }
    @Published var hotKeyDisplay: String { didSet { defaults.set(hotKeyDisplay, forKey: "hotKeyDisplay") } }

    // "Capture Text" shortcut, default ⇧⌘1
    @Published var textHotKeyCode: Int { didSet { defaults.set(textHotKeyCode, forKey: "textHotKeyCode") } }
    @Published var textHotKeyModifiers: Int { didSet { defaults.set(textHotKeyModifiers, forKey: "textHotKeyModifiers") } }
    @Published var textHotKeyDisplay: String { didSet { defaults.set(textHotKeyDisplay, forKey: "textHotKeyDisplay") } }
    /// Keep the original line breaks when copying recognized text.
    @Published var keepLineBreaks: Bool { didSet { defaults.set(keepLineBreaks, forKey: "keepLineBreaks") } }

    /// Also put every new capture on the clipboard.
    @Published var copyOnCapture: Bool { didSet { defaults.set(copyOnCapture, forKey: "copyOnCapture") } }
    /// How many captures the library keeps.
    @Published var libraryLimit: Int { didSet { defaults.set(libraryLimit, forKey: "libraryLimit") } }

    private init() {
        defaults.register(defaults: [
            "hotKeyCode": kVK_ANSI_2,
            "hotKeyModifiers": cmdKey | shiftKey,
            "hotKeyDisplay": "⇧⌘2",
            "textHotKeyCode": kVK_ANSI_1,
            "textHotKeyModifiers": cmdKey | shiftKey,
            "textHotKeyDisplay": "⇧⌘1",
            "keepLineBreaks": true,
            "copyOnCapture": true,
            "libraryLimit": 200,
        ])
        hotKeyCode = defaults.integer(forKey: "hotKeyCode")
        hotKeyModifiers = defaults.integer(forKey: "hotKeyModifiers")
        hotKeyDisplay = defaults.string(forKey: "hotKeyDisplay") ?? "⇧⌘2"
        textHotKeyCode = defaults.integer(forKey: "textHotKeyCode")
        textHotKeyModifiers = defaults.integer(forKey: "textHotKeyModifiers")
        textHotKeyDisplay = defaults.string(forKey: "textHotKeyDisplay") ?? "⇧⌘1"
        keepLineBreaks = defaults.bool(forKey: "keepLineBreaks")
        copyOnCapture = defaults.bool(forKey: "copyOnCapture")
        libraryLimit = defaults.integer(forKey: "libraryLimit")
    }
}
