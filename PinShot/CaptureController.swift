import AppKit
import ScreenCaptureKit

/// Runs a capture: freezes the screen, lets you pick an area or a window,
/// then saves it to the library and pins it where it was.
/// What a capture is for.
enum CaptureMode {
    case pin    // save to the library and pin it on screen
    case text   // just copy the text / QR code in it
}

@MainActor
final class CaptureController {
    static let shared = CaptureController()

    private var overlays: [SelectionOverlayWindow] = []
    private var busy = false
    private var mode: CaptureMode = .pin

    // MARK: Area / window

    func startCapture(mode: CaptureMode = .pin) {
        guard !busy else { return }
        guard ensurePermission() else { return }
        busy = true
        self.mode = mode
        let hint = mode == .text
            ? "Drag over text or a QR code to copy it  ·  Click a window  ·  Esc to cancel"
            : "Drag to capture an area  ·  Click a window  ·  Esc to cancel"
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                let windows = ScreenCapturer.pickableWindows(in: content)
                var created: [SelectionOverlayWindow] = []
                for screen in NSScreen.screens {
                    let image = try await ScreenCapturer.capture(screen: screen, content: content)
                    created.append(SelectionOverlayWindow(screen: screen, image: image, windows: windows, hint: hint) { result in
                        CaptureController.shared.finish(result)
                    })
                }
                overlays = created
                NSApp.activate(ignoringOtherApps: true)
                let mouse = NSEvent.mouseLocation
                for o in overlays { o.orderFrontRegardless() }
                (overlays.first { NSMouseInRect(mouse, $0.frame, false) } ?? overlays.first)?.makeKeyAndFocus()
            } catch {
                busy = false
                showPermissionAlert()
            }
        }
    }

    private func finish(_ result: SelectionResult?) {
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        busy = false
        guard let result else { return }

        switch result {
        case .area(let image, let frame, let scale):
            handle(image, frame: frame, scale: scale)
        case .window(let picked, let fallback, let scale):
            Task {
                let image = (try? await ScreenCapturer.capture(window: picked.window, scale: scale)) ?? fallback
                handle(image, frame: picked.frame, scale: scale)
            }
        }
    }

    private func handle(_ image: CGImage, frame: NSRect, scale: CGFloat) {
        switch mode {
        case .pin:
            deliver(image, frame: frame, scale: scale)
        case .text:
            Task { await TextRecognizer.copyContent(of: image, near: frame) }
        }
    }


    // MARK: Full screen

    func captureFullScreen() {
        guard !busy, ensurePermission() else { return }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        busy = true
        Task {
            defer { busy = false }
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
                  let image = try? await ScreenCapturer.capture(screen: screen, content: content) else {
                showPermissionAlert(); return
            }
            // Pin it at half size in the middle of the screen
            let f = screen.visibleFrame
            let size = NSSize(width: screen.frame.width / 2, height: screen.frame.height / 2)
            let frame = NSRect(x: f.midX - size.width / 2, y: f.midY - size.height / 2, width: size.width, height: size.height)
            deliver(image, frame: frame, scale: screen.backingScaleFactor)
        }
    }

    // MARK: Result

    private func deliver(_ image: CGImage, frame: NSRect, scale: CGFloat) {
        guard let capture = CaptureStore.shared.add(image, scale: scale) else { return }
        if AppSettings.shared.copyOnCapture {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([NSImage(cgImage: image, size: frame.size)])
        }
        PinManager.shared.pin(image: image, capture: capture, frame: frame)
    }

    // MARK: Permission

    private func ensurePermission() -> Bool {
        if ScreenCapturer.hasPermission { return true }
        ScreenCapturer.requestPermission()   // adds PinShot to the list in System Settings
        showPermissionAlert()
        return false
    }

    private func showPermissionAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "PinShot needs Screen Recording permission"
        alert.informativeText = """
        To take screenshots, turn on PinShot in System Settings → Privacy & Security → Screen Recording. \
        Then quit and reopen PinShot.

        Captures stay on your Mac — nothing is recorded or uploaded.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit & Reopen PinShot")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        case .alertSecondButtonReturn:
            Self.relaunch()
        default:
            break
        }
    }

    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}

enum SelectionResult {
    /// Cropped image, its frame in global screen points, and the screen's pixel scale.
    case area(CGImage, NSRect, CGFloat)
    /// A picked window, a cropped fallback image, and the screen's pixel scale.
    case window(PickableWindow, CGImage, CGFloat)
}

// MARK: - Overlay window

final class SelectionOverlayWindow: NSWindow {
    private let selectionView: SelectionView

    init(screen: NSScreen, image: CGImage, windows: [PickableWindow], hint: String,
         onDone: @escaping (SelectionResult?) -> Void) {
        selectionView = SelectionView(image: image, screen: screen, windows: windows, hint: hint, onDone: onDone)
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        isOpaque = true
        hasShadow = false
        backgroundColor = .black
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        contentView = selectionView
    }

    override var canBecomeKey: Bool { true }

    func makeKeyAndFocus() {
        makeKey()
        makeFirstResponder(selectionView)
    }
}

// MARK: - Selection view

final class SelectionView: NSView {
    private let image: CGImage
    private let screen: NSScreen
    /// Windows on this screen, in view coordinates, front-most first.
    private let windows: [(PickableWindow, NSRect)]
    private let onDone: (SelectionResult?) -> Void
    private let hint: String

    private var dragStart: NSPoint?
    private var selection: NSRect?
    private var hovered: (PickableWindow, NSRect)?
    private var mouse: NSPoint = .zero
    private var finished = false

    init(image: CGImage, screen: NSScreen, windows: [PickableWindow], hint: String,
         onDone: @escaping (SelectionResult?) -> Void) {
        self.image = image
        self.screen = screen
        self.hint = hint
        self.onDone = onDone
        let origin = screen.frame.origin
        self.windows = windows.compactMap { w in
            let local = w.frame.offsetBy(dx: -origin.x, dy: -origin.y)
            let visible = local.intersection(NSRect(origin: .zero, size: screen.frame.size))
            return visible.isEmpty ? nil : (w, local)
        }
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate],
                                       owner: self))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.draw(image, in: bounds)

        let highlight = selection ?? hovered?.1
        // Dim everything except the selection / hovered window
        let dim = NSBezierPath(rect: bounds)
        if let highlight { dim.append(NSBezierPath(rect: highlight)); dim.windingRule = .evenOdd }
        NSColor.black.withAlphaComponent(0.38).setFill()
        dim.fill()

        if let selection {
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selection.insetBy(dx: -0.5, dy: -0.5))
            border.lineWidth = 1
            border.stroke()
            let scale = screen.backingScaleFactor
            drawLabel("\(Int(selection.width * scale)) × \(Int(selection.height * scale))",
                      at: NSPoint(x: selection.maxX + 8, y: selection.minY - 26))
        } else if let (_, rect) = hovered {
            NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
            rect.fill()
            NSColor.controlAccentColor.setStroke()
            let border = NSBezierPath(rect: rect.insetBy(dx: 1.5, dy: 1.5))
            border.lineWidth = 3
            border.stroke()
        }

        if selection == nil {
            drawLabel(hint,
                      at: NSPoint(x: bounds.midX, y: bounds.maxY - 70), centered: true)
        }
    }

    private func drawLabel(_ text: String, at point: NSPoint, centered: Bool = false) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        var origin = point
        if centered { origin.x -= size.width / 2 }
        // keep on screen
        origin.x = min(max(origin.x, 8), bounds.width - size.width - 20)
        origin.y = min(max(origin.y, 8), bounds.height - size.height - 12)
        let box = NSRect(x: origin.x - 8, y: origin.y - 4, width: size.width + 16, height: size.height + 8)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        (text as NSString).draw(at: origin, withAttributes: attrs)
    }

    // MARK: Mouse

    override func mouseMoved(with event: NSEvent) {
        mouse = convert(event.locationInWindow, from: nil)
        let newHover = windows.first { $0.1.contains(mouse) }
        if newHover?.0.window.windowID != hovered?.0.window.windowID {
            hovered = newHover
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        selection = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let p = convert(event.locationInWindow, from: nil)
        let rect = NSRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
            .intersection(bounds)
        selection = rect.width >= 3 || rect.height >= 3 ? rect.integral : nil
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        if let selection, selection.width >= 4, selection.height >= 4 {
            guard let cropped = crop(selection) else { return done(nil) }
            done(.area(cropped, selection.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY), screen.backingScaleFactor))
        } else if let (picked, local) = hovered, let fallback = crop(local.intersection(bounds)) {
            done(.window(picked, fallback, screen.backingScaleFactor))
        } else {
            selection = nil
            needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { done(nil) } else { super.keyDown(with: event) }   // Esc
    }

    override func cancelOperation(_ sender: Any?) { done(nil) }

    private func crop(_ rect: NSRect) -> CGImage? {
        let s = CGFloat(image.width) / bounds.width
        let pixelRect = CGRect(x: rect.minX * s, y: (bounds.height - rect.maxY) * s,
                               width: rect.width * s, height: rect.height * s).integral
        return image.cropping(to: pixelRect)
    }



    private func done(_ result: SelectionResult?) {
        guard !finished else { return }
        finished = true
        onDone(result)
    }
}
