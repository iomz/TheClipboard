import AppKit

/// Applies the single bundled icon without reading or writing preferences.
/// Never writes bundle/Finder metadata.
final class ApplicationIconController {
    let image: NSImage?
    private let applyImage: (NSImage) -> Void
    private let schedule: (@escaping () -> Void) -> Void
    private var reapplicationPending = false

    static func loadImage(bundle: Bundle) -> NSImage? {
        guard let url = bundle.url(forResource: "AppIcon", withExtension: "icns"),
              let image = NSImage(contentsOf: url), image.isValid,
              !image.representations.isEmpty else { return nil }
        return image
    }

    init(bundle: Bundle = .main,
         applyImage: @escaping (NSImage) -> Void = { NSApp.applicationIconImage = $0 },
         schedule: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }) {
        image = Self.loadImage(bundle: bundle)
        self.applyImage = applyImage
        self.schedule = schedule
        applyIcon()
    }

    // Startup and activation-policy changes can publish the bundle's Dock icon
    // after an early setter. Reassert after the lifecycle callback, not a timer.
    func scheduleReapplication() {
        guard !reapplicationPending else { return }
        reapplicationPending = true
        schedule { [weak self] in
            guard let self else { return }
            self.reapplicationPending = false
            self.applyIcon()
        }
    }

    private func applyIcon() {
        if let image { applyImage(image) }
    }
}
