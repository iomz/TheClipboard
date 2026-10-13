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
        let sourceInfo = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])), format: nil
        ) as! [String: Any]
        precondition(about.applicationName == "The Clipboard")
        precondition(about.version == sourceInfo["CFBundleShortVersionString"] as? String)
        precondition(about.build == sourceInfo["CFBundleVersion"] as? String)
        let domain = "com.iomz.TheClipboard.Test.Identity.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        precondition(defaults.object(forKey: "SUEnableAutomaticChecks") == nil)
        precondition(defaults.object(forKey: "ApplicationIconSelection") == nil)
        let icons = ApplicationIconController(bundle: bundle, applyImage: { _ in })
        precondition(icons.image != nil)
        precondition(defaults.object(forKey: "ApplicationIconSelection") == nil)
        print("Identity checks passed: bundle/executable/About, fresh TheClipboard storage/defaults and single application icon.")
    }
}
