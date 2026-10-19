import SwiftUI
import AppKit

@MainActor
final class LibraryWindowController {
    static let shared = LibraryWindowController()
    private var window: NSWindow?

    func show() {
        CaptureStore.shared.reload()
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: LibraryView()))
            w.title = "PinShot Library"
            w.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            w.setContentSize(NSSize(width: 720, height: 520))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct LibraryView: View {
    @ObservedObject private var store = CaptureStore.shared
    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(store.captures.isEmpty ? "No captures yet" : "\(store.captures.count) captures")
                    .font(.headline)
                Spacer()
                Button("Open Folder") { NSWorkspace.shared.open(store.folder) }
                Button("Clear All…", role: .destructive) { confirmClear() }
                    .disabled(store.captures.isEmpty)
            }
            .padding(12)
            Divider()

            if store.captures.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder").font(.system(size: 36, weight: .light))
                    Text("Press \(AppSettings.shared.hotKeyDisplay) to take your first capture")
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(store.captures) { capture in
                            LibraryItem(capture: capture)
                        }
                    }
                    .padding(14)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 300)
    }

    private func confirmClear() {
        let alert = NSAlert()
        alert.messageText = "Delete all captures?"
        alert.informativeText = "This removes every screenshot in the PinShot library. Open pins stay open."
        alert.addButton(withTitle: "Delete All")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { store.clearAll() }
    }
}

struct LibraryItem: View {
    let capture: Capture
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let thumb = Thumbnails.image(for: capture.url) {
                    Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
                }
            }
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .padding(6)
            .background(Color.primary.opacity(hovering ? 0.08 : 0.04), in: RoundedRectangle(cornerRadius: 8))

            Text(capture.date, format: .dateTime.day().month().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { PinManager.shared.pin(capture: capture) }
        .onDrag { NSItemProvider(contentsOf: capture.url) ?? NSItemProvider() }
        .help("Double-click to pin · Drag into any app")
        .contextMenu {
            Button("Pin to Screen") { PinManager.shared.pin(capture: capture) }
            Button("Copy Image") {
                if let image = NSImage(contentsOf: capture.url) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([image])
                }
            }
            Button("Copy Text") {
                guard let source = CGImageSourceCreateWithURL(capture.url as CFURL, nil),
                      let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
                let mouse = NSEvent.mouseLocation
                Task { await TextRecognizer.copyContent(of: cg, near: NSRect(x: mouse.x, y: mouse.y, width: 1, height: 1)) }
            }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([capture.url]) }
            Divider()
            Button("Delete", role: .destructive) { CaptureStore.shared.delete(capture) }
        }
    }
}
