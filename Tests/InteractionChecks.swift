import AppKit
import ClipboardCore
@testable import ClipboardPlatform

@main
enum InteractionChecks {
    static func main() throws {
        _ = NSApplication.shared
        let match = PickerShortcut.opensHistoryManager
        precondition(match(49, [.command, .shift], true))
        precondition(match(49, [.command, .shift, .capsLock], true))
        precondition(!match(49, [.command, .shift], false))
        for modifiers: NSEvent.ModifierFlags in [[], [.command], [.shift], [.control], [.command, .shift, .option], [.command, .shift, .control]] {
            precondition(!match(49, modifiers, true))
        }
        for key: UInt16 in [36, 76, 53, 35, 45, 125, 126, 9] {
            precondition(!match(key, [.command, .shift], true))
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TheClipboard-interaction-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let history = ClipboardLibrary(store: try FileEntryStore(root: root))
        let entry = ClipboardEntry(pasteboardItems: [.init(ordinal: 0, representations: [
            .init(typeIdentifier: "public.utf8-plain-text", data: Data("Disposable favorite fixture".utf8))
        ])])
        try history.capture(entry)
        let board = NSPasteboard(name: .init("com.iomz.TheClipboard.Test.Interaction.\(UUID().uuidString)"))
        defer { board.clearContents() }
        let capture = PasteboardCapture(history: history, pasteboard: board)
        var handoffs = 0
        let picker = PickerWindowController(history: history, capture: capture, onOpenHistoryManager: {
            handoffs += 1
        }, onFeedback: { _ in preconditionFailure("Shortcut must not paste") })
        let shortcutChangeCount = board.changeCount
        picker.openHistoryManagerFromPicker()
        precondition(handoffs == 1 && board.changeCount == shortcutChangeCount)
        precondition(history.allEntries().count == 1 && history.allEntries()[0].id == entry.id)
        let manager = HistoryManagerWindowController(history: history, capture: capture, onFeedback: { _ in
            preconditionFailure("Unexpected fixture feedback")
        }, onWindowVisibilityChanged: { _ in })

        func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap(descendants)
        }
        let views = descendants(manager.window!.contentView!)
        let button = views.compactMap { $0 as? NSButton }.first { $0.title == "Favorite" }!
        let table = views.compactMap { $0 as? NSTableView }.first!
        func currentRow() -> HistoryManagerRowCell {
            manager.tableView(table, viewFor: table.tableColumns[0], row: 0) as! HistoryManagerRowCell
        }
        precondition(button.image != nil && button.accessibilityLabel() == "Add to favorites")
        precondition(currentRow().favoriteIndicator.state == .off && !currentRow().favoriteIndicator.isHidden)
        precondition(currentRow().favoriteIndicator.accessibilityLabel() == "Add to favorites")
        let before = board.changeCount
        button.performClick(nil)
        precondition(history.allEntries()[0].isFavorite)
        let favoriteReload = try FileEntryStore(root: root).loadAll()[0]
        precondition(favoriteReload.isFavorite)
        precondition(button.title == "Unfavorite" && button.accessibilityLabel() == "Remove from favorites")
        let cell = currentRow()
        precondition(cell.favoriteIndicator.state == .on && cell.favoriteIndicator.image != nil)
        precondition(cell.favoriteIndicator.accessibilityLabel() == "Remove from favorites")
        cell.backgroundStyle = .emphasized
        precondition(cell.favoriteIndicator.contentTintColor == .alternateSelectedControlTextColor)
        cell.backgroundStyle = .normal
        precondition(cell.favoriteIndicator.contentTintColor == .secondaryLabelColor)
        button.performClick(nil)
        precondition(!history.allEntries()[0].isFavorite)
        let unfavoriteReload = try FileEntryStore(root: root).loadAll()[0]
        precondition(!unfavoriteReload.isFavorite)
        precondition(currentRow().favoriteIndicator.state == .off)

        // Row star toggles its own entry without the detail-pane button.
        let star = (table.view(atColumn: 0, row: 0, makeIfNecessary: true) as! HistoryManagerRowCell).favoriteIndicator
        star.performClick(nil)
        let starReload = try FileEntryStore(root: root).loadAll()[0]
        precondition(history.allEntries()[0].isFavorite && starReload.isFavorite)
        precondition(currentRow().favoriteIndicator.state == .on && button.title == "Unfavorite")
        (table.view(atColumn: 0, row: 0, makeIfNecessary: true) as! HistoryManagerRowCell).favoriteIndicator.performClick(nil)
        precondition(!history.allEntries()[0].isFavorite)

        // Storage summary reflects whole-library count and payload bytes.
        let storage = views.compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "History storage usage" }!
        precondition(history.storageUsage().entryCount == 1 && history.storageUsage().byteCount == entry.payloadByteCount)
        precondition(storage.stringValue.hasPrefix("1 item · "), storage.stringValue)
        precondition(board.changeCount == before, "Favorite action changed fixture clipboard")

        // Delete key removes the selected entry; modified Delete does not.
        let second = ClipboardEntry(pasteboardItems: [.init(ordinal: 0, representations: [
            .init(typeIdentifier: "public.utf8-plain-text", data: Data("Second disposable fixture".utf8))
        ])])
        try history.capture(second)
        precondition(storage.stringValue.hasPrefix("2 items · "), storage.stringValue)
        func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                             context: nil, characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}", isARepeat: false, keyCode: code)!
        }
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        table.keyDown(with: key(51, .command))
        precondition(history.allEntries().count == 2, "Modified Delete must not remove entries")
        table.keyDown(with: key(51))
        let deleteReload = try FileEntryStore(root: root).loadAll()
        precondition(history.allEntries().map(\.id) == [entry.id] && deleteReload.count == 1)
        precondition(table.selectedRow == 0 && storage.stringValue.hasPrefix("1 item · "))
        table.keyDown(with: key(117))
        precondition(history.allEntries().isEmpty && table.selectedRow == -1 && storage.stringValue.hasPrefix("0 items · "))
        precondition(!manager.window!.isVisible, "Tests must not activate a Manager window")
        print("Interaction checks passed: picker-only shortcut/handoff without paste; favorite button and row star, persistence, SF Symbol, accessibility and selection tint; storage summary; Delete key removal.")
    }
}
