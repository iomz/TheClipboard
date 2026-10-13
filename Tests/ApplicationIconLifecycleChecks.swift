import AppKit
import CryptoKit

private func fingerprint() -> Data {
    Data(SHA256.hash(data: NSApp.applicationIconImage.tiffRepresentation ?? Data()))
}

private final class IconLaunchProbe: NSObject, NSApplicationDelegate {
    private var controller: ApplicationIconController!
    private let suite = "com.iomz.TheClipboard.Test.IconLaunch.\(UUID().uuidString)"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let defaults = UserDefaults(suiteName: suite)!
        let saved = CommandLine.arguments[1]
        if saved != "fresh" { defaults.set(saved, forKey: "ApplicationIconSelection") }
        controller = ApplicationIconController()
        precondition(controller.image != nil)
        let selectedFingerprint = fingerprint()
        precondition(NSApp.setActivationPolicy(.regular))
        // Exercise a late publisher during launch, then the actual main queue.
        NSApp.applicationIconImage = NSImage(systemSymbolName: "questionmark.square", accessibilityDescription: nil)!
        precondition(fingerprint() != selectedFingerprint)
        controller.scheduleReapplication()
        controller.scheduleReapplication()
        DispatchQueue.main.async {
            precondition(fingerprint() == selectedFingerprint, "Launch overwrite was not repaired")
            precondition(defaults.string(forKey: "ApplicationIconSelection") == (saved == "fresh" ? nil : saved))
            self.controller.scheduleReapplication()
            DispatchQueue.main.async {
                precondition(fingerprint() == selectedFingerprint, "Single icon changed after lifecycle callback")
                defaults.removePersistentDomain(forName: self.suite)
                print("Real AppKit launch probe passed: \(saved), single icon, policy transition and deferred overwrite repair. Dock visual HAT remains required.")
                fflush(stdout)
                exit(0)
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        controller?.scheduleReapplication()
    }
}

@main
private enum IconLaunchChecks {
    static func main() {
        let app = NSApplication.shared
        let delegate = IconLaunchProbe()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
