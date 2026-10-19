import AppKit
import Combine
import ImageIO
import UniformTypeIdentifiers

struct Capture: Identifiable, Hashable {
    let url: URL
    let date: Date
    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
}

/// The library of past captures, stored as PNG files in
/// ~/Library/Application Support/PinShot/Captures/
@MainActor
final class CaptureStore: ObservableObject {
    static let shared = CaptureStore()

    @Published private(set) var captures: [Capture] = []

    let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("PinShot/Captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private init() { reload() }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])) ?? []
        captures = urls
            .filter { $0.pathExtension.lowercased() == "png" }
            .map { url in
                let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return Capture(url: url, date: date)
            }
            .sorted { $0.date > $1.date }
    }

    /// Saves a new capture. `scale` is the screen's pixels-per-point, stored as DPI
    /// so the PNG opens at the right size elsewhere.
    func add(_ image: CGImage, scale: CGFloat) -> Capture? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let base = "PinShot \(formatter.string(from: Date()))"
        var url = folder.appendingPathComponent(base + ".png")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) (\(n)).png"); n += 1
        }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return nil }
        let dpi = 72 * scale
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }

        let capture = Capture(url: url, date: Date())
        captures.insert(capture, at: 0)
        trim()
        return capture
    }

    func delete(_ capture: Capture) {
        try? FileManager.default.removeItem(at: capture.url)
        captures.removeAll { $0 == capture }
    }

    func clearAll() {
        captures.forEach { try? FileManager.default.removeItem(at: $0.url) }
        captures.removeAll()
    }

    private func trim() {
        let limit = max(AppSettings.shared.libraryLimit, 1)
        guard captures.count > limit else { return }
        for old in captures[limit...] { try? FileManager.default.removeItem(at: old.url) }
        captures.removeLast(captures.count - limit)
    }
}

/// Small downscaled previews for the library grid.
@MainActor
enum Thumbnails {
    private static let cache = NSCache<NSURL, NSImage>()

    static func image(for url: URL, maxPixels: Int = 480) -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
