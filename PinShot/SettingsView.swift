import SwiftUI
import AppKit
import ServiceManagement

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "PinShot Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var hasPermission = ScreenCapturer.hasPermission

    private let limits = [50, 100, 200, 500, 1000]

    var body: some View {
        Form {
            Section("Capturing") {
                LabeledContent("Capture & pin") { ShortcutRecorder(slot: .capture) }
                LabeledContent("Capture text") { ShortcutRecorder(slot: .text) }
                Toggle("Copy every capture to the clipboard", isOn: $settings.copyOnCapture)
                Text("Drag to capture an area, or click to capture a single window. Captures stay pinned on top of everything; Capture Text copies the text or QR code instead.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Text recognition") {
                Toggle("Keep line breaks when copying text", isOn: $settings.keepLineBreaks)
            }

            Section("Library") {
                Picker("Keep the last", selection: $settings.libraryLimit) {
                    ForEach(limits, id: \.self) { Text("\($0) captures").tag($0) }
                }
                Button("Open Library") { LibraryWindowController.shared.show() }
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = "Couldn't change this: \(error.localizedDescription)"
                        }
                    }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }

            Section("Permissions") {
                HStack {
                    Image(systemName: hasPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(hasPermission ? .green : .orange)
                    Text(hasPermission ? "Screen Recording is on." : "Screen Recording is off — PinShot can't take screenshots.")
                    Spacer()
                    if !hasPermission {
                        Button("Open Settings") {
                            ScreenCapturer.requestPermission()
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasPermission = ScreenCapturer.hasPermission
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// Click, then press a new key combination.
struct ShortcutRecorder: View {
    let slot: HotKeySlot
    @ObservedObject private var settings = AppSettings.shared
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Press shortcut…" : (slot == .capture ? settings.hotKeyDisplay : settings.textHotKeyDisplay)) {
            recording ? stop() : start()
        }
        .frame(minWidth: 120)
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        HotKeyCenter.shared.pause()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil } // Esc cancels
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
            let code = Int(event.keyCode)
            let mods = HotKeyCenter.carbonModifiers(from: flags)
            let display = HotKeyCenter.displayString(for: event)
            switch slot {
            case .capture:
                settings.hotKeyCode = code; settings.hotKeyModifiers = mods; settings.hotKeyDisplay = display
            case .text:
                settings.textHotKeyCode = code; settings.textHotKeyModifiers = mods; settings.textHotKeyDisplay = display
            }
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        HotKeyCenter.shared.resume()
    }
}
