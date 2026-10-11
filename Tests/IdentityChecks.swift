import AppKit
import ClipboardCore
import Foundation

@main enum IdentityChecks {
    static func main() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("TheClipboard-identity-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let support = ApplicationIdentity.supportDirectory(in: base)
        precondition(support.lastPathComponent == "TheClipboard")
        let store = try FileEntryStore(root: support.appendingPathComponent("Entries"))
        precondition(store.loadAll().isEmpty, "Fresh store must start empty")
        let bundle = Bundle(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
        precondition(bundle.bundleIdentifier == "com.iomz.TheClipboard")
        precondition(bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String == "TheClipboard")
        let about = AboutInformation(bundle: bundle)
        precondition(about.applicationName == "The Clipboard" && about.version == "0.4.2" && about.build == "7")
        let domain = "com.iomz.TheClipboard.Test.Identity.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        precondition(defaults.object(forKey: "SUEnableAutomaticChecks") == nil)
        precondition(defaults.object(forKey: ApplicationIconController.preferenceKey) == nil)
        let icons = ApplicationIconController(defaults: defaults, bundle: bundle, applyImage: { _ in })
        precondition(icons.selected == .dustlight)
        precondition(defaults.object(forKey: ApplicationIconController.preferenceKey) == nil)
        print("Identity checks passed: bundle/executable/About, fresh TheClipboard storage/defaults and Dustlight default.")
    }
}
