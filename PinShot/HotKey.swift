import AppKit
import Carbon.HIToolbox

/// Which global shortcut.
enum HotKeySlot: UInt32 {
    case capture = 1   // capture & pin
    case text = 2      // capture text
}

/// Manages PinShot's system-wide shortcuts (they work even when PinShot isn't the active app).
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    nonisolated(unsafe) private static var actions: [UInt32: () -> Void] = [:]
    private var refs: [HotKeySlot: EventHotKeyRef] = [:]
    private var handlerInstalled = false

    func start(capture: @escaping () -> Void, text: @escaping () -> Void) {
        HotKeyCenter.actions = [HotKeySlot.capture.rawValue: capture, HotKeySlot.text.rawValue: text]
        installHandler()
        resume()
    }

    /// Registers the shortcuts saved in Settings.
    func resume() {
        let s = AppSettings.shared
        register(.capture, keyCode: s.hotKeyCode, modifiers: s.hotKeyModifiers)
        register(.text, keyCode: s.textHotKeyCode, modifiers: s.textHotKeyModifiers)
    }

    /// Temporarily disables the shortcuts (used while recording a new one).
    func pause() {
        refs.values.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
    }

    private func register(_ slot: HotKeySlot, keyCode: Int, modifiers: Int) {
        if let old = refs[slot] { UnregisterEventHotKey(old) }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x50534854), id: slot.rawValue) // "PSHT"
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &ref)
        refs[slot] = ref
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let key = id.id
            DispatchQueue.main.async { HotKeyCenter.actions[key]?() }
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
