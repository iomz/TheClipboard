import CryptoKit
import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw NSError(domain: "DistributionChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

func plist(_ path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let value = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
        throw NSError(domain: "DistributionChecks", code: 2)
    }
    return value
}

do {
    let args = CommandLine.arguments
    let source = try plist(args[1])
    let app = URL(fileURLWithPath: args[2], isDirectory: true)
    let bundled = try plist(app.appendingPathComponent("Contents/Info.plist").path)
    for key in ["CFBundleIdentifier", "CFBundleName", "CFBundleDisplayName", "CFBundleExecutable", "CFBundleShortVersionString", "CFBundleVersion", "LSMinimumSystemVersion", "SUFeedURL", "SUPublicEDKey", "CFBundleIconName"] {
        try require(bundled[key] as? String == source[key] as? String, "Bundle metadata mismatch: \(key)")
    }
    try require(bundled["CFBundleIdentifier"] as? String == "com.iomz.TheClipboard", "Wrong new application identity")
    try require(bundled["CFBundleName"] as? String == "The Clipboard" && bundled["CFBundleDisplayName"] as? String == "The Clipboard", "Wrong application name")
    try require(app.lastPathComponent == "The Clipboard.app", "Wrong application bundle filename")
    try require(bundled["CFBundleExecutable"] as? String == "TheClipboard", "Wrong executable metadata")
    try require(bundled["SUFeedURL"] as? String == "https://iomz.github.io/TheClipboard/appcast.xml", "Unexpected feed")
    try require(bundled["SUEnableAutomaticChecks"] == nil, "Native consent is suppressed by bundle automatic-check override")
    try require(bundled["SUScheduledCheckInterval"] as? Double == 86400, "Default check interval must be 24 hours")
    for key in ["SUAutomaticallyUpdate", "SUAllowsAutomaticUpdates"] {
        try require(bundled[key] as? Bool == false, "Automatic updating enabled: \(key)")
    }
    try require(bundled["SUVerifyUpdateBeforeExtraction"] as? Bool == true, "Archive verification must precede extraction")
    guard let publicKeyString = bundled["SUPublicEDKey"] as? String, let publicKey = Data(base64Encoded: publicKeyString) else {
        throw NSError(domain: "DistributionChecks", code: 3)
    }
    let signingKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
    // Outer bundle is assembled from an explicit allowlist, not the repository.
    let contents = app.appendingPathComponent("Contents")
    let names = Set(try FileManager.default.contentsOfDirectory(atPath: contents.path))
    try require(names == ["Info.plist", "MacOS", "Frameworks", "Resources", "_CodeSignature"], "Unexpected bundle contents (possible runtime data)")
    let executables = try FileManager.default.contentsOfDirectory(atPath: contents.appendingPathComponent("MacOS").path)
    let frameworks = try FileManager.default.contentsOfDirectory(atPath: contents.appendingPathComponent("Frameworks").path)
    try require(executables == ["TheClipboard"], "Unexpected executables/secrets")
    try require(frameworks == ["Sparkle.framework"], "Unexpected frameworks/tools")
    let resources = try FileManager.default.contentsOfDirectory(atPath: contents.appendingPathComponent("Resources").path)
    try require(Set(resources) == ["Sparkle-LICENSE.txt", "AppIcon.icns", "Assets.car"], "Unexpected resources/secrets")
    try require(bundled["CFBundleIconName"] as? String == "AppIcon", "Missing modern Finder icon declaration")
    let catalogData = try Data(contentsOf: contents.appendingPathComponent("Resources/Assets.car"))
    try require(!catalogData.isEmpty, "Missing modern Finder icon catalog")
    try require(bundled["CFBundleIconFile"] as? String == "AppIcon.icns", "Missing application icon metadata")
    try require(source["CFBundleIconFile"] as? String == bundled["CFBundleIconFile"] as? String, "Icon metadata mismatch")
    let icon = try Data(contentsOf: contents.appendingPathComponent("Resources/AppIcon.icns"))
    try require(icon.prefix(4) == Data("icns".utf8) && icon.count > 8, "Invalid/missing application icon")
    let license = try String(contentsOf: contents.appendingPathComponent("Resources/Sparkle-LICENSE.txt"), encoding: .utf8)
    try require(license.contains("Andy Matuschak") && license.contains("EXTERNAL LICENSES"), "Missing Sparkle attribution")
    let frameworkInfo = try plist(contents.appendingPathComponent("Frameworks/Sparkle.framework/Resources/Info.plist").path)
    try require(frameworkInfo["CFBundleShortVersionString"] as? String == "2.10.0", "Unpinned Sparkle framework")

    if args.count > 4 && !args[3].isEmpty {
        let document = try XMLDocument(contentsOf: URL(fileURLWithPath: args[3]), options: [.nodeLoadExternalEntitiesNever])
        let items = try document.nodes(forXPath: "/rss/channel/item")
        try require(!items.isEmpty, "Empty appcast")
        var currentFound = false
        var versions = Set<String>()
        for case let item as XMLElement in items {
            func text(_ name: String) -> String? { item.elements(forName: name).first?.stringValue }
            guard let enclosure = item.elements(forName: "enclosure").first,
                  let urlString = enclosure.attribute(forName: "url")?.stringValue,
                  let url = URL(string: urlString),
                  let signatureString = enclosure.attribute(forName: "sparkle:edSignature")?.stringValue,
                  let signature = Data(base64Encoded: signatureString),
                  let length = enclosure.attribute(forName: "length")?.stringValue,
                  let version = text("sparkle:version"),
                  let shortVersion = text("sparkle:shortVersionString") else {
                throw NSError(domain: "DistributionChecks", code: 4, userInfo: [NSLocalizedDescriptionKey: "Missing signed enclosure/version metadata"])
            }
            try require(versions.insert(version).inserted, "Duplicate build in appcast")
            let filename = "TheClipboard-\(shortVersion)-arm64.dmg"
            try require(urlString == "https://github.com/iomz/TheClipboard/releases/download/v\(shortVersion)/\(filename)", "Unexpected release URL or legacy appcast")
            try require(url.lastPathComponent == filename, "Unexpected archive name")
            let archive = try Data(contentsOf: URL(fileURLWithPath: args[4]).appendingPathComponent(filename))
            try require(String(archive.count) == length, "Archive length mismatch")
            try require(signingKey.isValidSignature(signature, for: archive), "EdDSA signature does not match embedded public key")
            var tamperedArchive = archive
            tamperedArchive.append(0)
            try require(!signingKey.isValidSignature(signature, for: tamperedArchive), "Tampered archive unexpectedly accepted")
            if version == bundled["CFBundleVersion"] as? String {
                currentFound = true
                try require(shortVersion == bundled["CFBundleShortVersionString"] as? String, "Appcast version mismatch")
                try require(text("sparkle:minimumSystemVersion") == bundled["LSMinimumSystemVersion"] as? String, "Minimum OS mismatch")
                try require(text("sparkle:hardwareRequirements") == "arm64", "Missing arm64 requirement")
            }
        }
        try require(currentFound, "Current build missing from appcast")
        print("Appcast XML, release URLs, versions, archive sizes and EdDSA signatures verified against bundled public key.")
    }
    print("Distribution metadata, pinned framework and bundle allowlist checks passed.")
} catch {
    fputs("Distribution check failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
