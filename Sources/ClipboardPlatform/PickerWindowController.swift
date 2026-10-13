import AppKit
import ClipboardCore
import Foundation
import OSLog

public struct PickerBadgePreviewState {
    public private(set) var isShiftDown = false

    public init() {}

    public mutating func updateShift(isDown: Bool) { isShiftDown = isDown }
    public mutating func reset() { isShiftDown = false }

    public func badge(for entry: ClipboardEntry) -> String {
        guard isShiftDown, PasteboardRestorer.plainText(for: entry) != nil else {
            return entry.compactTypeLabel
        }
        return "TXT"
    }
}

public enum PickerMode {
    case normal
    case favorite
}

public enum PickerShortcut {
    public static func opensHistoryManager(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, pickerIsKey: Bool) -> Bool {
        let shortcutModifiers = modifiers.intersection([.command, .shift, .control, .option])
        return pickerIsKey && keyCode == 49 && shortcutModifiers == [.command, .shift]
    }
}

public final class PickerWindowController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private static let pasteLogger = Logger(subsystem: "com.iomz.TheClipboard", category: "Paste")
    private static let badgeViewTag = 0x434842
    private let history: ClipboardLibrary
    private let capture: PasteboardCapture
    private let onFeedback: (String) -> Void
    private let onOpenHistoryManager: () -> Void
    let panel: NSPanel
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let countLabel = NSTextField(labelWithString: "")
    private var rows: [ClipboardEntry] = []
    public private(set) var mode: PickerMode = .normal
    var destinationApplication: NSRunningApplication?
    // Internal seams let regression tests exercise the real handoff/failure
    // path without requesting permissions, activating apps or posting keys.
    var ensurePasteAccess: () -> Bool = PasteCommand.ensureEventPostingAccess
    var postPaste: (pid_t) -> Bool = { PasteCommand.post(to: $0) }
    var frontmostPID: () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier }
    var activateDestination: (NSRunningApplication) -> Bool = { $0.activate(options: []) }
    private var lastExternalApplication: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?
    private var historyObserver: NSObjectProtocol?
    private var keyMonitor: Any?
    private var isDismissing = false
    private var badgePreview = PickerBadgePreviewState()
    private var hoverWorkItem: DispatchWorkItem?
    private var hoverDismissWorkItem: DispatchWorkItem?
    private var hoverGeneration: UInt = 0
    private var hoverDismissGeneration: UInt = 0
    private var hoverRegion = PickerHoverRegionState()
    private var scrollObserver: NSObjectProtocol?
    private var hoverPreview: ClipboardEntryHoverPreview?

    public var latestExternalApplication: NSRunningApplication? { lastExternalApplication }

    public init(history: ClipboardLibrary, capture: PasteboardCapture, onOpenHistoryManager: @escaping () -> Void = {}, onFeedback: @escaping (String) -> Void) {
        self.history = history
        self.capture = capture
        self.onFeedback = onFeedback
        self.onOpenHistoryManager = onOpenHistoryManager
        self.panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 520),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: true
        )
        super.init()
        hoverPreview = ClipboardEntryHoverPreview(parentWindow: panel)
        hoverPreview?.onPointerEntered = { [weak self] in self?.previewPointerEntered() }
        hoverPreview?.onPointerExited = { [weak self] in self?.previewPointerExited() }
        panel.delegate = self
        lastExternalApplication = NSWorkspace.shared.frontmostApplication
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let app = NSWorkspace.shared.frontmostApplication
            if app?.processIdentifier != NSRunningApplication.current.processIdentifier {
                self.lastExternalApplication = app
            }
        }
        historyObserver = NotificationCenter.default.addObserver(
            forName: .clipboardLibraryDidChange, object: history, queue: .main
        ) { [weak self] _ in
            guard let self, self.panel.isVisible else { return }
            self.reloadRows(query: self.searchField.stringValue, preservingSelection: true)
        }
        configurePanel()
        configureContent()
    }

    deinit {
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        if let historyObserver { NotificationCenter.default.removeObserver(historyObserver) }
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        cancelHoverPreview()
        removeKeyMonitor()
    }

    /// Carbon handles this shortcut globally, including while the panel is open.
    public func handleFavoriteShortcut() {
        if panel.isVisible {
            setMode(mode == .normal ? .favorite : .normal)
        } else {
            show(mode: .favorite)
        }
    }

    func setMode(_ mode: PickerMode, preservingSelection: Bool = true) {
        self.mode = mode
        searchField.placeholderString = mode == .favorite ? "Search favorite clips" : "Search saved clips"
        reloadRows(query: searchField.stringValue, preservingSelection: preservingSelection)
    }

    public func show(mode: PickerMode = .normal) {
        if panel.isVisible {
            setMode(mode)
            return
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        destinationApplication = frontmost?.processIdentifier == NSRunningApplication.current.processIdentifier
            ? lastExternalApplication : frontmost
        badgePreview.reset()
        badgePreview.updateShift(isDown: NSEvent.modifierFlags.contains(.shift))
        Self.pasteLogger.info("picker opened destinationPID=\(self.destinationApplication?.processIdentifier ?? 0, privacy: .public) frontmostWasSelf=\(frontmost?.processIdentifier == NSRunningApplication.current.processIdentifier, privacy: .public)")
        searchField.stringValue = ""
        setMode(mode, preservingSelection: false)
        positionNearPointer()
        panel.makeKeyAndOrderFront(nil)
        searchField.becomeFirstResponder()
        installKeyMonitor()
    }

    private func configurePanel() {
        panel.title = "The Clipboard"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .windowBackgroundColor
        panel.hasShadow = true
    }

    private func configureContent() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 520))
        searchField.placeholderString = "Search saved clips"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("entry"))
        column.width = 468
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 38
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self
        tableView.doubleAction = #selector(activateRichPaste)
        tableView.target = self
        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.contentView.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
        ) { [weak self] _ in self?.cancelHoverPreview() }

        countLabel.textColor = .secondaryLabelColor
        countLabel.font = .systemFont(ofSize: 11)
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(searchField)
        root.addSubview(scroll)
        root.addSubview(countLabel)
        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            searchField.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            scroll.bottomAnchor.constraint(equalTo: countLabel.topAnchor, constant: -8),
            countLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            countLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
        ])
        panel.contentView = root
    }

    private func positionNearPointer() {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = panel.frame.size
        let gap: CGFloat = 18
        // Prefer below/right of pointer; clamp to the pointer's display's usable frame.
        var origin = NSPoint(x: pointer.x + gap, y: pointer.y - size.height - gap)
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        panel.setFrameOrigin(origin)
    }

    func reloadRows(query: String = "", preservingSelection: Bool = false) {
        cancelHoverPreview()
        let selectedID = preservingSelection && rows.indices.contains(tableView.selectedRow)
            ? rows[tableView.selectedRow].id : nil
        let previousRow = tableView.selectedRow
        rows = history.search(query).filter { mode == .normal || $0.isFavorite }
        tableView.reloadData()
        let modeLabel = mode == .favorite ? "Favorites" : "Normal"
        countLabel.stringValue = "\(modeLabel) · \(rows.count) items · ⌥⌘C switch · ↵ paste · ⇧↵ plain · ⇧⌘Space Manager"
        if let selectedID, let index = rows.firstIndex(where: { $0.id == selectedID }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            if index != previousRow { tableView.scrollRowToVisible(index) }
        } else if !rows.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
        }
    }

    public func controlTextDidChange(_ notification: Notification) {
        reloadRows(query: searchField.stringValue)
    }

    public func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        let entry = rows[row]
        let cell = PickerHoverRowCell()
        cell.onHover = { [weak self] isInside in
            if isInside { self?.hoveredRowEntered(entry.id) }
            else { self?.hoveredRowExited(entry.id) }
        }
        let title = NSTextField(labelWithString: entry.preview.replacingOccurrences(of: "\n", with: " "))
        title.font = .systemFont(ofSize: 13)
        title.lineBreakMode = .byTruncatingTail
        let badge = NSTextField(labelWithString: badgePreview.badge(for: entry))
        badge.tag = Self.badgeViewTag
        badge.font = .systemFont(ofSize: 9, weight: .semibold)
        badge.textColor = .secondaryLabelColor
        badge.drawsBackground = true
        badge.backgroundColor = .quaternaryLabelColor
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 4
        badge.alignment = .center
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)
        badge.setContentHuggingPriority(.required, for: .horizontal)
        let favorite = NSTextField(labelWithString: entry.isFavorite ? "★" : "")
        favorite.font = .systemFont(ofSize: 10)
        favorite.textColor = .tertiaryLabelColor
        favorite.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = NSStackView(views: [badge, title, favorite])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        title.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
            row.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            if event.type == .flagsChanged {
                let shiftIsDown = event.modifierFlags.contains(.shift)
                guard self.badgePreview.isShiftDown != shiftIsDown else { return event }
                self.badgePreview.updateShift(isDown: shiftIsDown)
                self.reloadBadgeRowsPreservingSelection()
                return event
            }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if PickerShortcut.opensHistoryManager(keyCode: event.keyCode, modifiers: modifiers, pickerIsKey: self.panel.isKeyWindow) {
                self.openHistoryManagerFromPicker()
                return nil
            }
            if modifiers.contains(.control), event.keyCode == 45 { self.moveSelection(1); return nil } // Ctrl-N
            if modifiers.contains(.control), event.keyCode == 35 { self.moveSelection(-1); return nil } // Ctrl-P
            switch event.keyCode {
            case 53: self.dismiss(restoreDestination: true); return nil // Escape
            case 126: self.moveSelection(-1); return nil
            case 125: self.moveSelection(1); return nil
            case 36, 76:
                if event.modifierFlags.contains(.shift) { self.activatePlainPaste() }
                else { self.activateRichPaste() }
                return nil
            default: return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
    }

    func openHistoryManagerFromPicker() {
        // Unlike paste/Escape, this does not reactivate the old destination.
        dismiss()
        onOpenHistoryManager()
    }

    private func reloadBadgeRowsPreservingSelection() {
        let visibleRows = tableView.rows(in: tableView.visibleRect)
        guard visibleRows.location != NSNotFound else { return }
        for row in visibleRows.location..<NSMaxRange(visibleRows) where rows.indices.contains(row) {
            guard let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false),
                  let badge = cell.viewWithTag(Self.badgeViewTag) as? NSTextField else { continue }
            badge.stringValue = badgePreview.badge(for: rows[row])
        }
    }

    private func hoveredRowEntered(_ entryID: UUID) {
        guard panel.isVisible, rows.contains(where: { $0.id == entryID }) else { return }
        let isNewTarget = hoverRegion.entryID != entryID
        if isNewTarget {
            cancelHoverPreview()
            hoverRegion.enterRow(entryID)
        } else {
            hoverRegion.enterRow(entryID)
            cancelHoverDismissal()
            if hoverPreview?.isVisible == true || hoverWorkItem != nil { return }
        }
        hoverWorkItem?.cancel()
        hoverGeneration &+= 1
        let generation = hoverGeneration
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.panel.isVisible, self.hoverGeneration == generation,
                  self.hoverRegion.entryID == entryID, self.hoverRegion.pointerOverRow,
                  let row = self.rows.firstIndex(where: { $0.id == entryID }) else { return }
            let visibleRows = self.tableView.rows(in: self.tableView.visibleRect)
            guard visibleRows.location != NSNotFound,
                  row >= visibleRows.location, row < NSMaxRange(visibleRows) else { return }
            let rowRect = self.tableView.convert(self.tableView.rect(ofRow: row), to: nil)
            let screenRect = self.panel.convertToScreen(rowRect)
            self.hoverWorkItem = nil
            self.hoverPreview?.show(model: ClipboardEntryPreviewModel(entry: self.rows[row]), anchoredTo: screenRect)
        }
        hoverWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }

    private func hoveredRowExited(_ entryID: UUID) {
        guard hoverRegion.exitRow(entryID) else { return }
        if hoverPreview?.isVisible == true {
            scheduleHoverDismissal()
        } else {
            cancelHoverPreview()
        }
    }

    private func previewPointerEntered() {
        guard hoverPreview?.isVisible == true, hoverRegion.entryID != nil else { return }
        hoverRegion.enterPreview()
        cancelHoverDismissal()
    }

    private func previewPointerExited() {
        guard hoverPreview?.isVisible == true, hoverRegion.entryID != nil else { return }
        hoverRegion.exitPreview()
        scheduleHoverDismissal()
    }

    private func scheduleHoverDismissal() {
        cancelHoverDismissal()
        let generation = hoverDismissGeneration
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.hoverDismissGeneration == generation, self.hoverRegion.shouldDismiss else { return }
            self.cancelHoverPreview()
        }
        hoverDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    private func cancelHoverDismissal() {
        hoverDismissWorkItem?.cancel()
        hoverDismissWorkItem = nil
        hoverDismissGeneration &+= 1
    }

    private func cancelHoverPreview() {
        hoverWorkItem?.cancel()
        hoverWorkItem = nil
        hoverGeneration &+= 1
        cancelHoverDismissal()
        hoverRegion.reset()
        hoverPreview?.hide()
    }

    private func moveSelection(_ amount: Int) {
        guard !rows.isEmpty else { return }
        let current = max(tableView.selectedRow, 0)
        let next = min(max(current + amount, 0), rows.count - 1)
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    @objc private func activateRichPaste() { activate(plainTextOnly: false) }
    private func activatePlainPaste() { activate(plainTextOnly: true) }

    func activate(plainTextOnly: Bool) {
        guard rows.indices.contains(tableView.selectedRow) else { NSSound.beep(); return }
        let selectedIndex = tableView.selectedRow
        let entry = rows[selectedIndex]
        Self.pasteLogger.info("paste activation started plainTextOnly=\(plainTextOnly, privacy: .public) selectedIndex=\(selectedIndex, privacy: .public)")
        guard capture.restore(entry, plainTextOnly: plainTextOnly) else {
            Self.pasteLogger.error("paste restore failed")
            onFeedback("Could not restore clipboard representation")
            dismiss()
            return
        }
        Self.pasteLogger.info("paste restore succeeded")
        let destination = destinationApplication
        guard let destination, !destination.isTerminated else {
            dismiss()
            Self.pasteLogger.error("paste aborted: captured destination missing or terminated")
            onFeedback("Clipboard restored. Paste manually with ⌘V.")
            return
        }
        guard ensurePasteAccess() else {
            dismiss()
            Self.pasteLogger.error("paste aborted: event-synthesizing access unavailable; clipboard remains restored")
            onFeedback("Clipboard restored. Enable The Clipboard in System Settings › Privacy & Security › Accessibility, then try again.")
            return
        }
        dismiss()
        let targetPID = destination.processIdentifier
        let wasAlreadyFrontmost = frontmostPID() == targetPID
        let activationRequested = wasAlreadyFrontmost || activateDestination(destination)
        Self.pasteLogger.info("destination activation pid=\(targetPID, privacy: .public) alreadyFrontmost=\(wasAlreadyFrontmost, privacy: .public) requestAccepted=\(activationRequested, privacy: .public)")
        guard activationRequested else {
            Self.pasteLogger.error("paste aborted: destination activation request rejected")
            onFeedback("Clipboard restored. Destination did not activate; paste manually with ⌘V.")
            return
        }
        waitForDestinationAndPost(destination, entryID: entry.id, attemptsRemaining: 60)
    }

    func waitForDestinationAndPost(_ destination: NSRunningApplication, entryID: UUID, attemptsRemaining: Int) {
        let targetPID = destination.processIdentifier
        guard !destination.isTerminated else {
            Self.pasteLogger.error("paste aborted: destination terminated during focus handoff")
            onFeedback("Clipboard restored. Paste manually with ⌘V.")
            return
        }
        let observedPID = frontmostPID()
        guard observedPID == targetPID else {
            guard attemptsRemaining > 0 else {
                Self.pasteLogger.error("paste aborted: destination did not become frontmost; observedPID=\(observedPID ?? 0, privacy: .public)")
                onFeedback("Clipboard restored. Destination did not activate; paste manually with ⌘V.")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [weak self] in
                self?.waitForDestinationAndPost(destination, entryID: entryID, attemptsRemaining: attemptsRemaining - 1)
            }
            return
        }
        Self.pasteLogger.info("destination frontmost verified pid=\(targetPID, privacy: .public)")
        guard postPaste(targetPID) else {
            Self.pasteLogger.error("paste event creation failed targetPID=\(targetPID, privacy: .public)")
            onFeedback("Clipboard restored. Paste manually with ⌘V.")
            return
        }
        Self.pasteLogger.info("paste event pair dispatched targetPID=\(targetPID, privacy: .public)")
        do { try history.recordReuse(of: entryID) }
        catch { onFeedback("Paste dispatched, but could not save history order") }
    }

    private func dismiss(restoreDestination: Bool = false) {
        guard !isDismissing else { return }
        isDismissing = true
        let destination = destinationApplication
        removeKeyMonitor()
        badgePreview.reset()
        cancelHoverPreview()
        panel.orderOut(nil)
        destinationApplication = nil
        isDismissing = false
        if restoreDestination, let destination, !destination.isTerminated {
            _ = destination.activate(options: [])
        }
    }

    public func windowDidResignKey(_ notification: Notification) {
        guard notification.object as? NSWindow === panel, panel.isVisible, !isDismissing else { return }
        dismiss()
    }
}

private final class PickerHoverRowCell: NSTableCellView {
    var onHover: ((Bool) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover?(false)
    }
}
