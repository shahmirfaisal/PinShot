import AppKit
import SwiftUI
import Combine
import Vision
import UniformTypeIdentifiers

/// One floating screenshot.
@MainActor
final class PinController: NSObject, ObservableObject, NSWindowDelegate {
    let capture: Capture
    let cgImage: CGImage
    let image: NSImage
    let panel: PinPanel
    /// Size in points at 100%.
    let naturalSize: NSSize

    @Published var opacity: Double = 1 { didSet { panel.alphaValue = opacity } }
    @Published var clickThrough = false {
        didSet {
            panel.ignoresMouseEvents = clickThrough
            if clickThrough { Toast.show("Click-through on — unlock from the menu bar", near: panel.frame) }
        }
    }

    init(image: CGImage, capture: Capture, frame: NSRect) {
        self.capture = capture
        self.cgImage = image
        self.naturalSize = frame.size
        self.image = NSImage(cgImage: image, size: frame.size)
        self.panel = PinPanel()
        super.init()

        panel.delegate = self
        panel.controller = self
        panel.contentAspectRatio = frame.size
        panel.minSize = NSSize(width: 40, height: 40 * frame.height / max(frame.width, 1))
        panel.contentView = PinHostingView(rootView: PinView(pin: self))
        panel.setFrame(Self.fitted(frame), display: false)
    }

    func show() {
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = opacity
        }
    }

    // MARK: Actions

    func close() {
        panel.orderOut(nil)
        PinManager.shared.remove(self)
    }

    func copyImage() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        Toast.show("Copied image", near: panel.frame)
    }

    func copyText() {
        Task { await TextRecognizer.copyContent(of: cgImage, near: panel.frame) }
    }

    func save() {
        NSApp.activate(ignoringOtherApps: true)
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = capture.url.lastPathComponent
        savePanel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        savePanel.level = .floating + 1
        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }
        try? FileManager.default.removeItem(at: url)
        do {
            try FileManager.default.copyItem(at: capture.url, to: url)
            Toast.show("Saved", near: panel.frame)
        } catch {
            Toast.show("Couldn't save: \(error.localizedDescription)", near: panel.frame)
        }
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([capture.url])
    }

    // MARK: Size

    /// Scales the pin around its center. 1 = original size.
    func zoom(by factor: CGFloat) {
        let old = panel.frame
        var w = old.width * factor
        w = min(max(w, panel.minSize.width), naturalSize.width * 4)
        let h = w * naturalSize.height / naturalSize.width
        panel.setFrame(NSRect(x: old.midX - w / 2, y: old.midY - h / 2, width: w, height: h), display: true)
    }

    func actualSize() {
        let old = panel.frame
        panel.setFrame(NSRect(x: old.midX - naturalSize.width / 2, y: old.midY - naturalSize.height / 2,
                              width: naturalSize.width, height: naturalSize.height), display: true, animate: true)
    }

    /// Big captures are shrunk so the pin fits comfortably on screen.
    private static func fitted(_ frame: NSRect) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return frame }
        var f = frame
        let maxW = visible.width * 0.8, maxH = visible.height * 0.8
        let s = min(1, maxW / f.width, maxH / f.height)
        if s < 1 {
            let w = f.width * s, h = f.height * s
            f = NSRect(x: f.midX - w / 2, y: f.midY - h / 2, width: w, height: h)
        }
        f.origin.x = min(max(f.minX, visible.minX), visible.maxX - f.width)
        f.origin.y = min(max(f.minY, visible.minY), visible.maxY - f.height)
        return f
    }
}

/// Borderless floating window that can be resized from its edges and doesn't steal focus.
final class PinPanel: NSPanel {
    weak var controller: PinController?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .resizable, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        guard let c = controller else { return super.keyDown(with: event) }
        let cmd = event.modifierFlags.contains(.command)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch (cmd, key, event.keyCode) {
        case (_, _, 53), (true, "w", _): c.close()            // Esc, ⌘W
        case (true, "c", _): c.copyImage()
        case (true, "t", _): c.copyText()
        case (true, "s", _): c.save()
        case (true, "0", _): c.actualSize()
        case (true, "=", _), (true, "+", _): c.zoom(by: 1.15)
        case (true, "-", _): c.zoom(by: 1 / 1.15)
        default: super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) { keyDown(with: event); return true }
        return super.performKeyEquivalent(with: event)
    }
}

final class PinHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Pin UI

struct PinView: View {
    @ObservedObject var pin: PinController
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .top) {
            Image(nsImage: pin.image)
                .resizable()
                .interpolation(.high)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Drag anywhere to move · scroll or pinch to resize · double-click for 100%
            PinSurface(pin: pin)

            if hovering {
                toolbar
                    .padding(6)
                    .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.25), lineWidth: 0.5))
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .contextMenu { menu }
    }

    private var toolbar: some View {
        HStack(spacing: 2) {
            ToolButton(symbol: "xmark", help: "Close (Esc)") { pin.close() }
            Spacer(minLength: 4)
            ToolButton(symbol: "doc.on.doc", help: "Copy image (⌘C)") { pin.copyImage() }
            ToolButton(symbol: "text.viewfinder", help: "Copy text (⌘T)") { pin.copyText() }
            ToolButton(symbol: "square.and.arrow.down", help: "Save… (⌘S)") { pin.save() }
            FileDragHandle(url: pin.capture.url, image: pin.image)
                .frame(width: 26, height: 24)
                .overlay(Image(systemName: "hand.draw").font(.system(size: 12, weight: .medium)).allowsHitTesting(false))
                .help("Drag into another app")
            Menu {
                menu
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 26, height: 24)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var menu: some View {
        Button("Copy Image") { pin.copyImage() }
        Button("Copy Text") { pin.copyText() }
        Button("Save…") { pin.save() }
        Button("Show in Finder") { pin.revealInFinder() }
        Divider()
        Menu("Opacity") {
            ForEach([1.0, 0.75, 0.5, 0.25], id: \.self) { value in
                Button { pin.opacity = value } label: {
                    Text("\(Int(value * 100))%") + Text(pin.opacity == value ? "  ✓" : "")
                }
            }
        }
        Button("Click Through (lock)") { pin.clickThrough = true }
        Button("Actual Size") { pin.actualSize() }
        Divider()
        Button("Close") { pin.close() }
    }
}

struct ToolButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Moves the pin when dragged, resizes on scroll/pinch, 100% on double-click.
struct PinSurface: NSViewRepresentable {
    let pin: PinController
    func makeNSView(context: Context) -> PinSurfaceView { let v = PinSurfaceView(); v.pin = pin; return v }
    func updateNSView(_ nsView: PinSurfaceView, context: Context) { nsView.pin = pin }
}

final class PinSurfaceView: NSView {
    weak var pin: PinController?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { pin?.actualSize(); return }
        window?.makeKey()
        window?.performDrag(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 200 : event.scrollingDeltaY / 20
        guard delta != 0 else { return }
        pin?.zoom(by: 1 + delta)
    }

    override func magnify(with event: NSEvent) {
        pin?.zoom(by: 1 + event.magnification)
    }
}

/// Drags the screenshot file into other apps (Finder, Mail, Slack, browsers…).
struct FileDragHandle: NSViewRepresentable {
    let url: URL
    let image: NSImage
    func makeNSView(context: Context) -> FileDragView { let v = FileDragView(); v.url = url; v.image = image; return v }
    func updateNSView(_ v: FileDragView, context: Context) { v.url = url; v.image = image }
}

final class FileDragView: NSView, NSDraggingSource {
    var url: URL?
    var image: NSImage?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}   // don't move the window from here

    override func mouseDragged(with event: NSEvent) {
        guard let url else { return }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let p = convert(event.locationInWindow, from: nil)
        let size = image.map { s -> NSSize in
            let w: CGFloat = 120
            return NSSize(width: w, height: w * s.size.height / max(s.size.width, 1))
        } ?? NSSize(width: 64, height: 64)
        item.setDraggingFrame(NSRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height),
                              contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}

// MARK: - Managing pins

@MainActor
final class PinManager: ObservableObject {
    static let shared = PinManager()
    @Published private(set) var pins: [PinController] = []

    func pin(image: CGImage, capture: Capture, frame: NSRect) {
        let p = PinController(image: image, capture: capture, frame: frame)
        pins.append(p)
        p.show()
    }

    /// Re-pins a capture from the library, centered on the screen with the mouse.
    func pin(capture: Capture) {
        guard let source = CGImageSourceCreateWithURL(capture.url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dpi = (props?[kCGImagePropertyDPIWidth] as? CGFloat) ?? 144
        let scale = max(dpi / 72, 1)
        let size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let center = NSPoint(x: screen?.visibleFrame.midX ?? 400, y: screen?.visibleFrame.midY ?? 400)
        pin(image: image, capture: capture,
            frame: NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height))
    }

    func remove(_ pin: PinController) { pins.removeAll { $0 === pin } }

    func closeAll() {
        pins.forEach { $0.panel.orderOut(nil) }
        pins.removeAll()
    }

    func unlockAll() { pins.forEach { $0.clickThrough = false } }

    var hasLockedPins: Bool { pins.contains { $0.clickThrough } }
}

// MARK: - Text recognition

struct RecognizedContent {
    var lines: [String] = []
    /// Contents of QR codes / barcodes found in the image.
    var codes: [String] = []

    var isEmpty: Bool { lines.isEmpty && codes.isEmpty }

    /// What gets copied: codes first (e.g. a QR link), then the text.
    @MainActor
    var clipboardString: String {
        let text = AppSettings.shared.keepLineBreaks ? lines.joined(separator: "\n") : lines.joined(separator: " ")
        return (codes + (text.isEmpty ? [] : [text])).joined(separator: "\n")
    }

    var summary: String {
        var parts: [String] = []
        if !codes.isEmpty { parts.append(codes.count == 1 ? "QR/barcode" : "\(codes.count) codes") }
        if !lines.isEmpty { parts.append("\(lines.count) line\(lines.count == 1 ? "" : "s") of text") }
        return "Copied " + parts.joined(separator: " + ")
    }
}

enum TextRecognizer {
    /// Reads text and QR codes/barcodes in the image (on a background thread), using macOS's built-in Vision.
    nonisolated static func read(_ image: CGImage) async -> RecognizedContent {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let text = VNRecognizeTextRequest()
                text.recognitionLevel = .accurate
                text.usesLanguageCorrection = true
                text.automaticallyDetectsLanguage = true
                let codes = VNDetectBarcodesRequest()
                try? VNImageRequestHandler(cgImage: image).perform([text, codes])

                var result = RecognizedContent()
                result.lines = (text.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                var seen = Set<String>()
                result.codes = (codes.results ?? []).compactMap(\.payloadStringValue).filter { seen.insert($0).inserted }
                continuation.resume(returning: result)
            }
        }
    }

    /// Just the text, joined with line breaks.
    nonisolated static func recognize(_ image: CGImage) async -> String {
        await read(image).lines.joined(separator: "\n")
    }

    /// Reads the image and copies the result, showing a short message near `rect`.
    @MainActor
    static func copyContent(of image: CGImage, near rect: NSRect) async {
        let content = await read(image)
        if content.isEmpty {
            Toast.show("No text found", near: rect)
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(content.clipboardString, forType: .string)
        Toast.show(content.summary, near: rect)
    }
}

// MARK: - Toast

/// A small message that appears briefly under a pin.
@MainActor
enum Toast {
    private static var current: NSPanel?

    static func show(_ text: String, near rect: NSRect) {
        current?.orderOut(nil)
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.sizeToFit()
        let size = NSSize(width: label.frame.width + 24, height: label.frame.height + 12)

        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating + 1
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let box = NSView(frame: NSRect(origin: .zero, size: size))
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        box.layer?.cornerRadius = size.height / 2
        label.frame.origin = NSPoint(x: 12, y: 6)
        box.addSubview(label)
        panel.contentView = box

        var origin = NSPoint(x: rect.midX - size.width / 2, y: rect.minY - size.height - 8)
        if let visible = (NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main)?.visibleFrame,
           origin.y < visible.minY {
            origin.y = rect.minY + 8
        }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        current = panel

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel.animator().alphaValue = 0 },
                                                 completionHandler: { panel.orderOut(nil) })
        }
    }
}
