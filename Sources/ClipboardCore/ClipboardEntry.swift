import CryptoKit
import Foundation

public extension Notification.Name {
    static let clipboardLibraryDidChange = Notification.Name("TheClipboard.didChange")
}

public struct ClipboardRepresentation: Codable, Equatable, Sendable {
    public let typeIdentifier: String
    public let data: Data

    public init(typeIdentifier: String, data: Data) {
        self.typeIdentifier = typeIdentifier
        self.data = data
    }
}

public struct ClipboardPasteboardItem: Codable, Equatable, Sendable {
    public let ordinal: Int
    public let representations: [ClipboardRepresentation]

    public init(ordinal: Int, representations: [ClipboardRepresentation]) {
        self.ordinal = ordinal
        self.representations = representations
    }
}

public struct SourceApplication: Codable, Equatable, Sendable {
    public var bundleIdentifier: String?
    public var displayName: String?

    public init(bundleIdentifier: String? = nil, displayName: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
    }
}

public struct ClipboardEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let firstCapturedAt: Date
    public var lastCapturedAt: Date
    public var lastUsedAt: Date?
    public var orderingDate: Date { max(lastCapturedAt, lastUsedAt ?? lastCapturedAt) }
    public var sourceApplication: SourceApplication
    public var isFavorite: Bool
    public var pasteboardItems: [ClipboardPasteboardItem]
    public var plainText: String?
    public let canonicalIdentity: String

    public init(
        id: UUID = UUID(),
        capturedAt: Date = Date(),
        sourceApplication: SourceApplication = SourceApplication(),
        isFavorite: Bool = false,
        pasteboardItems: [ClipboardPasteboardItem],
        plainText: String? = nil
    ) {
        self.id = id
        self.firstCapturedAt = capturedAt
        self.lastCapturedAt = capturedAt
        self.sourceApplication = sourceApplication
        self.isFavorite = isFavorite
        self.pasteboardItems = pasteboardItems
        self.plainText = plainText
        self.canonicalIdentity = Self.identity(for: pasteboardItems)
    }

    /// Bytes of captured pasteboard payloads, excluding metadata and filesystem overhead.
    public var payloadByteCount: Int {
        pasteboardItems.reduce(0) { total, item in
            total + item.representations.reduce(0) { $0 + $1.data.count }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, firstCapturedAt, lastCapturedAt, lastUsedAt, sourceApplication, isFavorite
        case pasteboardItems, plainText, canonicalIdentity
    }

    public var preview: String {
        if let plainText, !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(plainText.prefix(240))
        }
        let types = pasteboardItems.flatMap(\.representations).map(\.typeIdentifier)
        if types.contains(where: { $0.hasPrefix("public.image") || $0 == "public.png" || $0 == "public.jpeg" || $0 == "public.tiff" }) {
            return "Image"
        }
        if types.contains(where: { $0 == "public.file-url" }) { return "File" }
        if types.contains(where: { $0 == "public.url" }) { return "URL" }
        if types.contains(where: { $0 == "public.rtf" || $0 == "public.rtfd" }) { return "Rich text" }
        if types.contains(where: { $0 == "public.html" }) { return "HTML" }
        return "Clipboard item"
    }

    public var typeSummary: String {
        let identifiers = Set(pasteboardItems.flatMap(\.representations).map(\.typeIdentifier))
        let hasFileReference = identifiers.contains("public.file-url")
        let hasImageData = identifiers.contains(where: Self.isImageType)
        if hasFileReference && hasImageData { return "Mixed file and image" }
        if hasFileReference { return "File" }
        if hasImageData { return "Image" }
        if identifiers.contains(where: { $0 == "public.url" }) { return "URL" }
        if identifiers.contains(where: { $0 == "public.rtf" || $0 == "public.rtfd" || $0 == "public.html" }) { return "Rich text" }
        return "Text"
    }

    public var compactTypeLabel: String {
        let identifiers = Set(pasteboardItems.flatMap(\.representations).map(\.typeIdentifier))
        let hasFileReference = identifiers.contains("public.file-url")
        let hasImageData = identifiers.contains(where: Self.isImageType)
        // Avoid hiding conflicting semantics behind arbitrary representation order.
        if hasFileReference && hasImageData { return "MIX" }
        if hasFileReference { return "FILE" }
        if hasImageData { return "IMG" }
        if identifiers.contains("public.url") { return "URL" }
        if identifiers.contains("public.rtf") || identifiers.contains("public.rtfd") { return "RTF" }
        if identifiers.contains("public.html") { return "HTML" }
        return "TXT"
    }

    private static func isImageType(_ identifier: String) -> Bool {
        identifier == "public.png" || identifier == "public.jpeg" || identifier == "public.tiff"
            || identifier == "public.heic" || identifier == "public.heif"
            || identifier == "public.image"
    }

    public static func extractPlainText(from representations: [ClipboardRepresentation]) -> String? {
        let priorities = ["public.utf8-plain-text", "public.plain-text", "public.utf16-external-plain-text"]
        for identifier in priorities {
            for representation in representations where representation.typeIdentifier == identifier {
                let encoding: String.Encoding = identifier == "public.utf16-external-plain-text" ? .utf16 : .utf8
                if let value = String(data: representation.data, encoding: encoding)
                    ?? String(data: representation.data, encoding: .utf16) {
                    return value
                }
            }
        }
        return nil
    }

    /// SHA-256 over versioned, length-framed bytes. Group order is significant;
    /// representation order within a group is canonicalized by lowercased type ID,
    /// then payload bytes. Derived text, timestamp, source, favorite, and UI data are excluded.
    public static func identity(for items: [ClipboardPasteboardItem]) -> String {
        var bytes = Data("TheClipboard\0canonical-v1\0".utf8)
        append(UInt64(items.count), to: &bytes)
        for (index, item) in items.enumerated() {
            append(UInt64(index), to: &bytes)
            let representations = item.representations.sorted {
                let left = $0.typeIdentifier.lowercased()
                let right = $1.typeIdentifier.lowercased()
                if left != right { return left < right }
                return $0.data.lexicographicallyPrecedes($1.data)
            }
            append(UInt64(representations.count), to: &bytes)
            for representation in representations {
                let typeBytes = Data(representation.typeIdentifier.lowercased().utf8)
                append(UInt64(typeBytes.count), to: &bytes)
                bytes.append(typeBytes)
                append(UInt64(representation.data.count), to: &bytes)
                bytes.append(representation.data)
            }
        }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private static func append(_ value: UInt64, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }
}

public struct CaptureResult: Equatable, Sendable {
    public let entry: ClipboardEntry
    public let wasDuplicate: Bool

    public init(entry: ClipboardEntry, wasDuplicate: Bool) {
        self.entry = entry
        self.wasDuplicate = wasDuplicate
    }
}

public protocol ClipboardEntryStore: AnyObject {
    func loadAll() -> [ClipboardEntry]
    func upsert(_ entry: ClipboardEntry) throws
    func remove(id: UUID) throws
}

public final class ClipboardLibrary {
    private let store: ClipboardEntryStore
    private let lock = NSLock()
    private var entries: [ClipboardEntry]

    public init(store: ClipboardEntryStore) {
        self.store = store
        self.entries = store.loadAll().sorted { $0.orderingDate > $1.orderingDate }
    }

    public func allEntries() -> [ClipboardEntry] {
        lock.lock(); defer { lock.unlock() }
        return entries
    }

    @discardableResult
    public func capture(_ incoming: ClipboardEntry, at date: Date = Date()) throws -> CaptureResult {
        lock.lock()
        var promoted = incoming
        do {
            let wasDuplicate: Bool
            if let index = entries.firstIndex(where: { $0.canonicalIdentity == incoming.canonicalIdentity }) {
                let existing = entries[index]
                promoted = ClipboardEntry(
                    id: existing.id,
                    capturedAt: existing.firstCapturedAt,
                    sourceApplication: incoming.sourceApplication,
                    isFavorite: existing.isFavorite,
                    pasteboardItems: incoming.pasteboardItems,
                    plainText: incoming.plainText
                )
                promoted.lastCapturedAt = date
                promoted.lastUsedAt = existing.lastUsedAt
                try store.upsert(promoted)
                entries.remove(at: index)
                wasDuplicate = true
            } else {
                promoted.lastCapturedAt = date
                try store.upsert(promoted)
                wasDuplicate = false
            }
            entries.insert(promoted, at: 0)
            lock.unlock()
            NotificationCenter.default.post(name: .clipboardLibraryDidChange, object: self)
            return CaptureResult(entry: promoted, wasDuplicate: wasDuplicate)
        } catch {
            lock.unlock()
            throw error
        }
    }

    /// Successful reuse updates ordering only. Persist before changing memory or
    /// notifying views; failed storage writes leave order and selection intact.
    public func recordReuse(of id: UUID, at date: Date = Date()) throws {
        lock.lock()
        do {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { lock.unlock(); return }
            var entry = entries[index]
            let newest = entries.map(\.orderingDate).max() ?? date
            entry.lastUsedAt = max(date, newest.addingTimeInterval(0.000001))
            try store.upsert(entry)
            entries.remove(at: index)
            entries.insert(entry, at: 0)
            lock.unlock()
            NotificationCenter.default.post(name: .clipboardLibraryDidChange, object: self)
        } catch {
            lock.unlock()
            throw error
        }
    }

    public func setFavorite(_ favorite: Bool, for id: UUID) throws {
        lock.lock()
        do {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { lock.unlock(); return }
            let old = entries[index]
            entries[index].isFavorite = favorite
            do { try store.upsert(entries[index]) }
            catch { entries[index] = old; throw error }
            lock.unlock()
            NotificationCenter.default.post(name: .clipboardLibraryDidChange, object: self)
        } catch {
            lock.unlock()
            throw error
        }
    }

    public func remove(id: UUID) throws {
        lock.lock()
        do {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { lock.unlock(); return }
            try store.remove(id: id)
            entries.remove(at: index)
            lock.unlock()
            NotificationCenter.default.post(name: .clipboardLibraryDidChange, object: self)
        } catch {
            lock.unlock()
            throw error
        }
    }

    public func storageUsage() -> (entryCount: Int, byteCount: Int) {
        lock.lock(); defer { lock.unlock() }
        return (entries.count, entries.reduce(0) { $0 + $1.payloadByteCount })
    }

    public func search(_ query: String) -> [ClipboardEntry] {
        lock.lock(); defer { lock.unlock() }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return entries }
        return entries.filter {
            $0.preview.localizedCaseInsensitiveContains(needle)
                || ($0.sourceApplication.displayName?.localizedCaseInsensitiveContains(needle) ?? false)
        }
    }
}
