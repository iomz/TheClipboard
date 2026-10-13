import AppKit
import Foundation

@main
enum ApplicationIconChecks {
    static func main() throws {
        _ = NSApplication.shared
        let previousImage = NSApp.applicationIconImage
        defer { NSApp.applicationIconImage = previousImage }
        let suite = "com.iomz.TheClipboard.Test.Icons.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let app = Bundle(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
        let protectedURLs = ["Info.plist", "Resources/AppIcon.icns", "Resources/Assets.car", "_CodeSignature/CodeResources"]
            .map { app.bundleURL.appendingPathComponent("Contents/\($0)") }
        let before = try protectedURLs.map { try Data(contentsOf: $0) }
        let expected = ApplicationIconController.loadImage(bundle: app)!.tiffRepresentation
        var displayedImage: Data?

        // Old selections must neither affect the single icon nor be rewritten.
        for saved in [nil, "dustlight", "lagoon", "unknown"] as [String?] {
            defaults.removeObject(forKey: "ApplicationIconSelection")
            if let saved { defaults.set(saved, forKey: "ApplicationIconSelection") }
            let snapshot = (defaults.persistentDomain(forName: suite) ?? [:]) as NSDictionary
            var callbacks: [() -> Void] = []
            var applied: [NSImage] = []
            let controller = ApplicationIconController(bundle: app,
                applyImage: { applied.append($0); NSApp.applicationIconImage = $0 },
                schedule: { callbacks.append($0) })
            precondition(applied.count == 1 && controller.image?.tiffRepresentation == expected)
            let displayed = NSApp.applicationIconImage.tiffRepresentation!
            if let displayedImage { precondition(displayed == displayedImage, "Legacy selection affected icon") }
            displayedImage = displayed
            controller.scheduleReapplication()
            controller.scheduleReapplication()
            precondition(callbacks.count == 1, "Lifecycle requests must coalesce")
            NSApp.applicationIconImage = NSImage(systemSymbolName: "questionmark.square", accessibilityDescription: nil)!
            callbacks.removeFirst()()
            precondition(applied.count == 2 && applied.last === controller.image)
            precondition(NSApp.applicationIconImage.tiffRepresentation == displayed)
            precondition(snapshot == (defaults.persistentDomain(forName: suite) ?? [:]) as NSDictionary)
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TheClipboard-icon-fixture-\(UUID().uuidString).app")
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = root.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": suite, "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: root.appendingPathComponent("Contents/Info.plist"))
        let missing = ApplicationIconController(bundle: Bundle(url: root)!, applyImage: { _ in
            preconditionFailure("Missing image must leave system fallback untouched")
        })
        precondition(missing.image == nil)
        try Data("not an icon".utf8).write(to: resources.appendingPathComponent("AppIcon.icns"))
        precondition(ApplicationIconController.loadImage(bundle: Bundle(url: root)!) == nil)
        let after = try protectedURLs.map { try Data(contentsOf: $0) }
        precondition(before == after, "Icon application modified signed bundle")
        print("Application icon checks passed: single image, ignored legacy selections, no preference writes, coalesced lifecycle repair, missing/corrupt fallback and unchanged signed bundle.")
    }
}
