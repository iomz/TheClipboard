import AppKit
import ClipboardCore
import Foundation

/// Persistent browsing/management surface. Shares repository and search semantics
/// with PickerWindowController; this window never synthesizes a paste command.
public final class HistoryManagerWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let history: ClipboardLibrary
    private let capture: PasteboardCapture
    private let onFeedback: (String) -> Void
    private let onWindowVisibilityChanged: (Bool) -> Void
    private let searchField = NSSearchField()
    private let scopeControl = NSSegmentedControl(labels: ["All", "Favorites"], trackingMode: .selectOne, target: nil, action: nil)
    private let tableView = HistoryManagerTableView()
    private let storageLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private let previewView = NSTextView()
    private let detailPreviewImage = ManagerPreviewImageView()
    private var detailPreviewImageHeight: NSLayoutConstraint!
    private let detailSourceImage = NSImageView()
    private let detailSourceLabel = ManagerDetailLabel(labelWithString: "")
    private let detailTypeLabel = ManagerDetailLabel(labelWithString: "")
    private let detailDateLabel = ManagerDetailLabel(labelWithString: "")
    private let favoriteButton = NSButton(title: "Favorite", target: nil, action: nil)
    private let copyButton = NSButton(title: "Copy", target: nil, action: nil)
    private let plainCopyButton = NSButton(title: "Copy as Plain Text", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
    private var entries: [ClipboardEntry] = []
    private var selectedEntryID: UUID?
    /// Row to select after a deletion so repeated Delete walks the list
    /// instead of jumping back to the top.
    private var rowAfterDeletion: Int?
    private var historyObserver: NSObjectProtocol?
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    public init(
        history: ClipboardLibrary,
        capture: PasteboardCapture,
        onFeedback: @escaping (String) -> Void,
        onWindowVisibilityChanged: @escaping (Bool) -> Void
    ) {
        self.history = history
        self.capture = capture
        self.onFeedback = onFeedback
        self.onWindowVisibilityChanged = onWindowVisibilityChanged
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "The Clipboard"
        window.minSize = NSSize(width: 760, height: 480)
        window.center()
        super.init(window: window)
        window.delegate = self
        configureContent()
        historyObserver = NotificationCenter.default.addObserver(
            forName: .clipboardLibraryDidChange, object: history, queue: .main
        ) { [weak self] _ in self?.reloadEntries(preservingSelection: true) }
        reloadEntries()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let historyObserver { NotificationCenter.default.removeObserver(historyObserver) }
    }

    public func showManager(focusSearch: Bool = false) {
        onWindowVisibilityChanged(true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if focusSearch { window?.makeFirstResponder(searchField) }
    }

    public func windowWillClose(_ notification: Notification) {
        onWindowVisibilityChanged(false)
    }

    private func configureContent() {
        guard let content = window?.contentView else { return }
        // NSWindow owns and sizes its content view. Keep its autoresizing
        // relationship to the window; only constrain the content's children.

        searchField.placeholderString = "Search all saved clips"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true

        scopeControl.selectedSegment = 0
        scopeControl.target = self
        scopeControl.action = #selector(scopeChanged)
        scopeControl.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("history-entry"))
        column.width = 490
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 66
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(selectionChanged)
        tableView.onDelete = { [weak self] in self?.deleteSelected() }
        let listScroll = NSScrollView()
        listScroll.documentView = tableView
        listScroll.hasVerticalScroller = true
        listScroll.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        let listPane = NSView()
        listPane.translatesAutoresizingMaskIntoConstraints = false
        listPane.addSubview(listScroll)
        listPane.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            listScroll.leadingAnchor.constraint(equalTo: listPane.leadingAnchor),
            listScroll.trailingAnchor.constraint(equalTo: listPane.trailingAnchor),
            listScroll.topAnchor.constraint(equalTo: listPane.topAnchor),
            listScroll.bottomAnchor.constraint(equalTo: listPane.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: listPane.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: listPane.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: listPane.leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: listPane.trailingAnchor, constant: -24),
        ])

        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.translatesAutoresizingMaskIntoConstraints = false
        split.addArrangedSubview(listPane)
        let detailPane = makeDetailPane()
        split.addArrangedSubview(detailPane)
        listPane.widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true

        storageLabel.font = .systemFont(ofSize: 11)
        storageLabel.textColor = .secondaryLabelColor
        storageLabel.lineBreakMode = .byTruncatingTail
        storageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        storageLabel.setAccessibilityLabel("History storage usage")

        let header = NSStackView(views: [searchField, scopeControl])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12
        header.addView(storageLabel, in: .trailing)
        header.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(header)
        content.addSubview(split)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            split.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            split.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            split.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),
            split.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
        // Original 760-point frame minimum cannot fit all existing controls.
        // Let AppKit account for margins/alignment insets; this minimum must not
        // constrain normal resizing or choose the divider's position.
        window?.contentMinSize = NSSize(width: content.fittingSize.width, height: window!.contentMinSize.height)
    }

    private func makeDetailPane() -> NSView {
        let pane = NSView()
        pane.translatesAutoresizingMaskIntoConstraints = false
        detailSourceImage.imageScaling = .scaleProportionallyUpOrDown
        detailSourceImage.translatesAutoresizingMaskIntoConstraints = false
        detailPreviewImage.imageScaling = .scaleProportionallyUpOrDown
        detailPreviewImage.translatesAutoresizingMaskIntoConstraints = false
        detailPreviewImage.isHidden = true
        detailSourceLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        detailTypeLabel.textColor = .secondaryLabelColor
        detailDateLabel.textColor = .secondaryLabelColor
        for label in [detailSourceLabel, detailTypeLabel, detailDateLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
        }

        previewView.isEditable = false
        previewView.isSelectable = true
        previewView.drawsBackground = false
        previewView.font = .systemFont(ofSize: 14)
        previewView.textContainerInset = NSSize(width: 8, height: 10)
        let previewScroll = NSScrollView()
        previewScroll.documentView = previewView
        previewScroll.hasVerticalScroller = true
        previewScroll.borderType = .bezelBorder
        previewScroll.translatesAutoresizingMaskIntoConstraints = false

        for button in [favoriteButton, copyButton, plainCopyButton, deleteButton] {
            button.bezelStyle = .rounded
            button.translatesAutoresizingMaskIntoConstraints = false
        }
        favoriteButton.target = self
        favoriteButton.action = #selector(toggleFavorite)
        favoriteButton.image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: "Favorite")
        favoriteButton.imagePosition = .imageLeading
        // Both action titles share one width; changing selection must never
        // change the detail pane's minimum fitting width through this button.
        favoriteButton.title = "Unfavorite"
        let favoriteWidth = favoriteButton.intrinsicContentSize.width
        favoriteButton.title = "Favorite"
        favoriteButton.widthAnchor.constraint(equalToConstant: max(favoriteWidth, favoriteButton.intrinsicContentSize.width)).isActive = true
        copyButton.target = self
        copyButton.action = #selector(copyRich)
        plainCopyButton.target = self
        plainCopyButton.action = #selector(copyPlain)
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelected)

        let buttons = NSStackView(views: [copyButton, plainCopyButton, favoriteButton, deleteButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(detailSourceImage)
        pane.addSubview(detailSourceLabel)
        pane.addSubview(detailTypeLabel)
        pane.addSubview(detailDateLabel)
        pane.addSubview(detailPreviewImage)
        pane.addSubview(previewScroll)
        pane.addSubview(buttons)
        detailPreviewImageHeight = detailPreviewImage.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            detailSourceImage.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 18),
            detailSourceImage.topAnchor.constraint(equalTo: pane.topAnchor, constant: 18),
            detailSourceImage.widthAnchor.constraint(equalToConstant: 32),
            detailSourceImage.heightAnchor.constraint(equalToConstant: 32),
            detailSourceLabel.leadingAnchor.constraint(equalTo: detailSourceImage.trailingAnchor, constant: 10),
            detailSourceLabel.centerYAnchor.constraint(equalTo: detailSourceImage.centerYAnchor),
            detailSourceLabel.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -12),
            detailTypeLabel.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 18),
            detailTypeLabel.topAnchor.constraint(equalTo: detailSourceImage.bottomAnchor, constant: 12),
            detailTypeLabel.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -18),
            detailDateLabel.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 18),
            detailDateLabel.topAnchor.constraint(equalTo: detailTypeLabel.bottomAnchor, constant: 4),
            detailDateLabel.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -18),
            detailPreviewImage.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 18),
            detailPreviewImage.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -18),
            detailPreviewImage.topAnchor.constraint(equalTo: detailDateLabel.bottomAnchor, constant: 14),
            detailPreviewImageHeight,
            previewScroll.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 18),
            previewScroll.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -18),
            previewScroll.topAnchor.constraint(equalTo: detailPreviewImage.bottomAnchor),
            previewScroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -14),
            buttons.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 18),
            buttons.trailingAnchor.constraint(lessThanOrEqualTo: pane.trailingAnchor, constant: -18),
            buttons.bottomAnchor.constraint(equalTo: pane.bottomAnchor, constant: -16),
        ])
        setDetail(nil)
        return pane
    }

    public func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard entries.indices.contains(row) else { return nil }
        let entry = entries[row]
        let cell = HistoryManagerRowCell()
        cell.configureFavorite(entry.isFavorite)
        cell.favoriteIndicator.target = self
        cell.favoriteIndicator.action = #selector(toggleRowFavorite(_:))
        let sourceImage = NSImageView()
        sourceImage.translatesAutoresizingMaskIntoConstraints = false
        sourceImage.imageScaling = .scaleProportionallyUpOrDown
        sourceImage.image = icon(for: entry)

        let preview = NSTextField(labelWithString: entry.preview.replacingOccurrences(of: "\n", with: " "))
        preview.font = .systemFont(ofSize: 13, weight: .medium)
        preview.lineBreakMode = .byTruncatingTail
        let source = entry.sourceApplication.displayName ?? "Unknown app"
        let metadata = NSTextField(labelWithString: "\(entry.compactTypeLabel) · \(source) · \(dateFormatter.string(from: entry.lastCapturedAt))")
        metadata.font = .systemFont(ofSize: 11)
        metadata.textColor = .secondaryLabelColor
        preview.translatesAutoresizingMaskIntoConstraints = false
        metadata.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(sourceImage)
        cell.addSubview(preview)
        cell.addSubview(metadata)
        cell.addSubview(cell.favoriteIndicator)
        NSLayoutConstraint.activate([
            sourceImage.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            sourceImage.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            sourceImage.widthAnchor.constraint(equalToConstant: 28),
            sourceImage.heightAnchor.constraint(equalToConstant: 28),
            preview.leadingAnchor.constraint(equalTo: sourceImage.trailingAnchor, constant: 10),
            preview.trailingAnchor.constraint(equalTo: cell.favoriteIndicator.leadingAnchor, constant: -8),
            preview.topAnchor.constraint(equalTo: cell.topAnchor, constant: 14),
            metadata.leadingAnchor.constraint(equalTo: preview.leadingAnchor),
            metadata.trailingAnchor.constraint(equalTo: preview.trailingAnchor),
            metadata.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 4),
            cell.favoriteIndicator.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
            cell.favoriteIndicator.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            cell.favoriteIndicator.widthAnchor.constraint(equalToConstant: 14),
            cell.favoriteIndicator.heightAnchor.constraint(equalToConstant: 14),
        ])
        return cell
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        guard tableView.selectedRow >= 0, entries.indices.contains(tableView.selectedRow) else {
            selectedEntryID = nil
            setDetail(nil)
            return
        }
        selectedEntryID = entries[tableView.selectedRow].id
        setDetail(entries[tableView.selectedRow])
    }

    public func controlTextDidChange(_ notification: Notification) {
        reloadEntries(preservingSelection: true)
    }

    @objc private func scopeChanged() { reloadEntries(preservingSelection: true) }
    @objc private func selectionChanged() { tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification)) }

    private func reloadEntries(preservingSelection: Bool = false) {
        let previousID = preservingSelection ? selectedEntryID : nil
        let previousRow = tableView.selectedRow
        let fallbackRow = rowAfterDeletion ?? 0
        rowAfterDeletion = nil
        let searched = history.search(searchField.stringValue)
        entries = scopeControl.selectedSegment == 1 ? searched.filter(\.isFavorite) : searched
        tableView.reloadData()
        emptyLabel.stringValue = history.allEntries().isEmpty
            ? "Your saved clips will appear here."
            : (scopeControl.selectedSegment == 1 && searchField.stringValue.isEmpty ? "No favorite items yet." : "No items match your search.")
        emptyLabel.isHidden = !entries.isEmpty
        updateStorageLabel()
        if let previousID, let index = entries.firstIndex(where: { $0.id == previousID }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            selectedEntryID = previousID
            setDetail(entries[index])
            if index != previousRow { tableView.scrollRowToVisible(index) }
        } else if !entries.isEmpty {
            let index = min(fallbackRow, entries.count - 1)
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            selectedEntryID = entries[index].id
            setDetail(entries[index])
            if index != 0 { tableView.scrollRowToVisible(index) }
        } else {
            selectedEntryID = nil
            setDetail(nil)
        }
    }

    /// Totals cover the whole library, not the current search/scope filter.
    private func updateStorageLabel() {
        let usage = history.storageUsage()
        let size = ByteCountFormatter.string(fromByteCount: Int64(usage.byteCount), countStyle: .file)
        storageLabel.stringValue = "\(usage.entryCount) \(usage.entryCount == 1 ? "item" : "items") · \(size)"
    }

    private func setDetail(_ entry: ClipboardEntry?) {
        guard let entry else {
            detailSourceImage.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Clipboard item")
            detailSourceLabel.stringValue = "Select an item to inspect"
            detailTypeLabel.stringValue = ""
            detailDateLabel.stringValue = ""
            previewView.string = ""
            detailPreviewImage.image = nil
            detailPreviewImage.isHidden = true
            detailPreviewImageHeight.constant = 0
            favoriteButton.title = "Favorite"
            favoriteButton.isEnabled = false
            favoriteButton.contentTintColor = .secondaryLabelColor
            favoriteButton.setAccessibilityLabel("Add to favorites")
            copyButton.isEnabled = false
            plainCopyButton.isEnabled = false
            deleteButton.isEnabled = false
            return
        }
        let preview = ClipboardEntryPreviewModel(entry: entry)
        detailSourceImage.image = icon(for: entry)
        detailSourceLabel.stringValue = entry.sourceApplication.displayName ?? "Unknown app"
        detailTypeLabel.stringValue = preview.typeDescription
        detailDateLabel.stringValue = "Captured \(dateFormatter.string(from: entry.lastCapturedAt))"
        detailPreviewImage.image = preview.image
        detailPreviewImage.isHidden = preview.image == nil
        detailPreviewImageHeight.constant = preview.image == nil ? 0 : 150
        previewView.string = preview.text
        favoriteButton.title = entry.isFavorite ? "Unfavorite" : "Favorite"
        favoriteButton.contentTintColor = entry.isFavorite ? .controlAccentColor : .secondaryLabelColor
        favoriteButton.setAccessibilityLabel(entry.isFavorite ? "Remove from favorites" : "Add to favorites")
        favoriteButton.isEnabled = true
        copyButton.isEnabled = true
        plainCopyButton.isEnabled = entry.plainText != nil
        deleteButton.isEnabled = true
    }

    private func icon(for entry: ClipboardEntry) -> NSImage? {
        guard let bundleID = entry.sourceApplication.bundleIdentifier,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return NSImage(systemSymbolName: "app", accessibilityDescription: entry.sourceApplication.displayName ?? "Application")
        }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }

    private var selectedEntry: ClipboardEntry? { entries.first(where: { $0.id == selectedEntryID }) }

    @objc private func toggleFavorite() {
        guard let entry = selectedEntry else { return }
        do { try history.setFavorite(!entry.isFavorite, for: entry.id) }
        catch { onFeedback("Could not update favorite") }
    }

    /// Row star acts on its own row's entry, independent of the selection.
    @objc private func toggleRowFavorite(_ sender: NSButton) {
        let row = tableView.row(for: sender)
        guard entries.indices.contains(row) else { return }
        let entry = entries[row]
        do { try history.setFavorite(!entry.isFavorite, for: entry.id) }
        catch { onFeedback("Could not update favorite") }
    }

    @objc private func copyRich() { copy(plainTextOnly: false) }
    @objc private func copyPlain() { copy(plainTextOnly: true) }

    private func copy(plainTextOnly: Bool) {
        guard let entry = selectedEntry else { return }
        guard capture.restore(entry, plainTextOnly: plainTextOnly) else {
            onFeedback("Could not restore clipboard representation")
            return
        }
        do { try history.recordReuse(of: entry.id) }
        catch { onFeedback("Copied to clipboard, but could not save history order"); return }
        onFeedback("Copied to clipboard")
    }

    @objc private func deleteSelected() {
        guard let entry = selectedEntry else { return }
        rowAfterDeletion = tableView.selectedRow >= 0 ? tableView.selectedRow : nil
        do { try history.remove(id: entry.id) }
        catch { rowAfterDeletion = nil; onFeedback("Could not delete history item") }
    }
}

/// Delete/Forward Delete remove the selected entry; other keys keep table behavior.
final class HistoryManagerTableView: NSTableView {
    var onDelete: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let deleteKeys: Set<UInt16> = [51, 117] // kVK_Delete, kVK_ForwardDelete
        if deleteKeys.contains(event.keyCode),
           event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.function, .numericPad]).isEmpty,
           selectedRow >= 0 {
            onDelete?()
            return
        }
        super.keyDown(with: event)
    }
}

final class HistoryManagerRowCell: NSTableCellView {
    /// Clickable star: filled for favorites, outlined otherwise.
    let favoriteIndicator = NSButton()

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { updateFavoriteTint() }
    }

    func configureFavorite(_ isFavorite: Bool) {
        favoriteIndicator.translatesAutoresizingMaskIntoConstraints = false
        favoriteIndicator.isBordered = false
        favoriteIndicator.title = ""
        favoriteIndicator.imagePosition = .imageOnly
        favoriteIndicator.imageScaling = .scaleProportionallyUpOrDown
        favoriteIndicator.setButtonType(.toggle)
        favoriteIndicator.state = isFavorite ? .on : .off
        favoriteIndicator.image = NSImage(
            systemSymbolName: isFavorite ? "star.fill" : "star",
            accessibilityDescription: isFavorite ? "Favorite" : "Not favorite"
        )
        favoriteIndicator.alternateImage = nil
        favoriteIndicator.setAccessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
        favoriteIndicator.toolTip = isFavorite ? "Remove from favorites" : "Add to favorites"
        updateFavoriteTint()
    }

    private func updateFavoriteTint() {
        if backgroundStyle == .emphasized {
            favoriteIndicator.contentTintColor = .alternateSelectedControlTextColor
        } else {
            favoriteIndicator.contentTintColor = favoriteIndicator.state == .on ? .secondaryLabelColor : .tertiaryLabelColor
        }
    }
}

/// Preview scales inside the existing pane; source pixel width must not become
/// a split-view sizing preference. Height remains controlled by its constraint.
private final class ManagerPreviewImageView: NSImageView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: super.intrinsicContentSize.height)
    }
}

/// Long source/type/date text uses available detail width, not pane allocation.
private final class ManagerDetailLabel: NSTextField {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: super.intrinsicContentSize.height)
    }
}
