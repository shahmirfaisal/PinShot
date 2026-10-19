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

    /// Also put every new capture on the clipboard.
    @Published var copyOnCapture: Bool { didSet { defaults.set(copyOnCapture, forKey: "copyOnCapture") } }
    /// How many captures the library keeps.
    @Published var libraryLimit: Int { didSet { defaults.set(libraryLimit, forKey: "libraryLimit") } }

    private init() {
        defaults.register(defaults: [
            "hotKeyCode": kVK_ANSI_2,
            "hotKeyModifiers": cmdKey | shiftKey,
            "hotKeyDisplay": "⇧⌘2",
            "copyOnCapture": true,
            "libraryLimit": 200,
        ])
        hotKeyCode = defaults.integer(forKey: "hotKeyCode")
        hotKeyModifiers = defaults.integer(forKey: "hotKeyModifiers")
        hotKeyDisplay = defaults.string(forKey: "hotKeyDisplay") ?? "⇧⌘2"
        copyOnCapture = defaults.bool(forKey: "copyOnCapture")
        libraryLimit = defaults.integer(forKey: "libraryLimit")
    }
}
