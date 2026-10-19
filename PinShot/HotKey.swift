import AppKit
import Carbon.HIToolbox

/// Manages the system-wide shortcut (works even when ClipVault isn't the active app).
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    nonisolated(unsafe) private static var action: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerInstalled = false

    func start(action: @escaping () -> Void) {
        HotKeyCenter.action = action
        installHandler()
        resume()
    }

    /// Registers the shortcut saved in Settings.
    func resume() {
        let s = AppSettings.shared
        register(keyCode: s.hotKeyCode, modifiers: s.hotKeyModifiers)
    }

    /// Temporarily disables the shortcut (used while recording a new one).
    func pause() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func register(keyCode: Int, modifiers: Int) {
        pause()
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C5056), id: 1) // "CLPV"
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKeyCenter.action?() }
            return noErr
        }, 1, &eventType, nil, nil)
    }

    // MARK: Converting key presses for the shortcut recorder

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var m = 0
        if flags.contains(.command) { m |= cmdKey }
        if flags.contains(.shift) { m |= shiftKey }
        if flags.contains(.option) { m |= optionKey }
        if flags.contains(.control) { m |= controlKey }
        return m
    }

    static func displayString(for event: NSEvent) -> String {
        let f = event.modifierFlags
        var s = ""
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option) { s += "⌥" }
        if f.contains(.shift) { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        switch Int(event.keyCode) {
        case kVK_Space: s += "Space"
        case kVK_Return: s += "↩"
        case kVK_Tab: s += "⇥"
        case kVK_LeftArrow: s += "←"
        case kVK_RightArrow: s += "→"
        case kVK_UpArrow: s += "↑"
        case kVK_DownArrow: s += "↓"
        default: s += (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
        return s
    }
}
