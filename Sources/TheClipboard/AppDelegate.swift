import AppKit
import Carbon
import ClipboardCore
import ClipboardPlatform
import Foundation
import OSLog
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, SPUUpdaterDelegate {
    private static let updateLogger = Logger(subsystem: "com.iomz.TheClipboard", category: "Updates")
    private var statusItem: NSStatusItem!
    private var store: FileEntryStore!
    private var history: ClipboardLibrary!
    private var capture: PasteboardCapture!
    private var picker: PickerWindowController!
    private var historyManager: HistoryManagerWindowController!
    private var pickerHotkey: GlobalHotkey?
    private var favoritePickerHotkey: GlobalHotkey?
    private var plainTextPasteHotkey: GlobalHotkey?
    private var feedbackTimer: Timer?
    private var updaterController: SPUStandardUpdaterController!
    private var iconController: ApplicationIconController!

    private func configureUpdater() {
        // Sparkle owns consent, persisted preferences and scheduling. Do not
        // write preferences on launch or import the old application's defaults.
        updaterController = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        updaterController.startUpdater()
    }

    private func automaticChecksMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Automatically Check for Updates", action: #selector(toggleAutomaticChecks), keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func toggleAutomaticChecks() {
        updaterController.updater.automaticallyChecksForUpdates.toggle()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleAutomaticChecks) {
            menuItem.state = updaterController.updater.automaticallyChecksForUpdates ? .on : .off
            return !updaterController.updater.sessionInProgress
        }
        return true
    }

    func updater(_ updater: SPUUpdater, willScheduleUpdateCheckAfterDelay delay: TimeInterval) {
        Self.updateLogger.info("Sparkle scheduled check in \(delay, privacy: .public) seconds; interval \(updater.updateCheckInterval, privacy: .public) seconds")
    }

    func updaterWillNotScheduleUpdateCheck(_ updater: SPUUpdater) {
        Self.updateLogger.info("Sparkle automatic checks disabled; no scheduled check")
    }

    private func updateMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        item.target = updaterController
        return item
    }

    // Launch/signing smoke check without reading the clipboard, opening history,
    // registering shortcuts, sending network requests, or changing TCC.
    func checkDistributionConfiguration() -> Bool {
        iconController = ApplicationIconController()
        configureUpdater()
        configureStatusItem()
        configureMainMenu()
        let menus = [statusItem.menu, NSApp.mainMenu?.items.first?.submenu]
        let about = NSApp.mainMenu?.items.first?.submenu?.items.first
        let information = AboutInformation()
        let expectedInterval = (UserDefaults.standard.object(forKey: "SUScheduledCheckInterval") as? NSNumber)?.doubleValue
            ?? (Bundle.main.object(forInfoDictionaryKey: "SUScheduledCheckInterval") as? NSNumber)?.doubleValue
        print("Running bundle: \(Bundle.main.bundleURL.path); version \(information.version), build \(information.build)")
        print("Application icon: \(iconController.selected.title)")
        print("Automatic checks: \(updaterController.updater.automaticallyChecksForUpdates); interval: \(updaterController.updater.updateCheckInterval); background downloads: \(updaterController.updater.automaticallyDownloadsUpdates)")
        return statusItem.menu?.items.filter { $0.title == "Application Icon" }.count == 1
            && iconController.menu.items.count == 2
            && iconController.menu.items.filter { $0.state == .on }.count == 1
            && iconController.selected.rawValue == (UserDefaults.standard.string(forKey: ApplicationIconController.preferenceKey) ?? "dustlight")
            && iconController.selectedImage != nil
            && updaterController.updater.canCheckForUpdates
            && about?.target === self
            && about?.action == #selector(showAbout)
            && information.version == Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            && information.build == Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            && updaterController.updater.automaticallyChecksForUpdates == UserDefaults.standard.bool(forKey: "SUEnableAutomaticChecks")
            && updaterController.updater.updateCheckInterval == expectedInterval
            && !updaterController.updater.automaticallyDownloadsUpdates
            && menus.allSatisfy { menu in
                menu?.items.contains { item in
                    item.title == "Check for Updates…"
                        && item.target === updaterController
                        && item.action == #selector(SPUStandardUpdaterController.checkForUpdates(_:))
                } == true && menu?.items.contains { item in
                    item.action == #selector(toggleAutomaticChecks) && item.target === self
                } == true
            }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        iconController = ApplicationIconController()
        do {
            let support: URL
            if let testDirectory = ProcessInfo.processInfo.environment["THECLIPBOARD_SUPPORT_DIRECTORY"] {
                support = URL(fileURLWithPath: testDirectory, isDirectory: true)
            } else {
                let applicationSupport = try FileManager.default.url(
                    for: .applicationSupportDirectory, in: .userDomainMask,
                    appropriateFor: nil, create: true
                )
                support = ApplicationIdentity.supportDirectory(in: applicationSupport)
            }
            store = try FileEntryStore(root: support.appendingPathComponent("Entries", isDirectory: true))
            history = ClipboardLibrary(store: store)
            capture = PasteboardCapture(history: history)
            capture.start()
            configureUpdater()
            configureStatusItem()
            configureMainMenu()
            picker = PickerWindowController(history: history, capture: capture, onOpenHistoryManager: { [weak self] in
                self?.historyManager.showManager(focusSearch: true)
            }) { [weak self] message in
                self?.showFeedback(message)
            }
            historyManager = HistoryManagerWindowController(history: history, capture: capture) { [weak self] message in
                self?.showFeedback(message)
            } onWindowVisibilityChanged: { [weak self] managerIsOpen in
                self?.setManagerActivationPolicy(managerIsOpen)
            }
            pickerHotkey = GlobalHotkey(id: 1, keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | optionKey)) { [weak self] in
                self?.picker.show()
            }
            plainTextPasteHotkey = GlobalHotkey(id: 2, keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
                self?.pasteCurrentClipboardAsPlainText()
            }
            favoritePickerHotkey = GlobalHotkey(id: 3, keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey | optionKey)) { [weak self] in
                self?.picker.handleFavoriteShortcut()
            }
            let pickerStatus = pickerHotkey?.register() ?? OSStatus(paramErr)
            let plainTextStatus = plainTextPasteHotkey?.register() ?? OSStatus(paramErr)
            let favoritePickerStatus = favoritePickerHotkey?.register() ?? OSStatus(paramErr)
            if pickerStatus != noErr || plainTextStatus != noErr || favoritePickerStatus != noErr {
                statusItem.button?.toolTip = "The Clipboard · Use menu to open (shortcut unavailable)"
            }

            // Explicit launches open the Manager. Background/login launchers can
            // pass --background to start capture without presenting a window.
            if !ProcessInfo.processInfo.arguments.contains("--background") {
                historyManager.showManager()
            }
            iconController.scheduleReapplication()
        } catch {
            NSApp.terminate(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        historyManager.showManager()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        iconController?.scheduleReapplication()
    }

    func applicationWillTerminate(_ notification: Notification) {
        capture?.stop()
        pickerHotkey?.unregister()
        favoritePickerHotkey?.unregister()
        plainTextPasteHotkey?.unregister()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "The Clipboard")
        statusItem.button?.toolTip = "The Clipboard · ⌥⌘V"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Fast Picker…", action: #selector(openPicker), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Favorite Picker…", action: #selector(openFavoritePicker), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open History Manager…", action: #selector(openHistoryManager), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Clipboard Representation Report…", action: #selector(showClipboardReport), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit The Clipboard", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        menu.insertItem(updateMenuItem(), at: menu.items.count - 1)
        menu.insertItem(automaticChecksMenuItem(), at: menu.items.count - 1)
        menu.insertItem(iconController.menuItem(), at: menu.items.count - 1)
        statusItem.menu = menu
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu(title: "The Clipboard")
        let about = NSMenuItem(title: "About The Clipboard", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)
        appMenu.addItem(updateMenuItem())
        appMenu.addItem(automaticChecksMenuItem())
        appMenu.addItem(.separator())
        let hide = NSMenuItem(title: "Hide The Clipboard", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hide.target = NSApp
        appMenu.addItem(hide)
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        hideOthers.target = NSApp
        appMenu.addItem(hideOthers)
        let showAll = NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        showAll.target = NSApp
        appMenu.addItem(showAll)
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit The Clipboard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        appMenu.addItem(quit)
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenu = NSMenu(title: "File")
        let showHistory = NSMenuItem(title: "Show History", action: #selector(openHistoryManagerFromMainMenu), keyEquivalent: "0")
        showHistory.target = self
        fileMenu.addItem(showHistory)
        fileMenu.addItem(.separator())
        fileMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(.separator())
        let bringAll = NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        bringAll.target = NSApp
        windowMenu.addItem(bringAll)
        let windowMenuItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    @objc private func openHistoryManagerFromMainMenu() { historyManager.showManager() }

    @objc private func showAbout() {
        var options = AboutInformation().panelOptions
        if let image = iconController.selectedImage { options[.applicationIcon] = image }
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc private func openPicker() { picker.show() }
    @objc private func openFavoritePicker() { picker.show(mode: .favorite) }
    @objc private func openHistoryManager() { historyManager.showManager() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func pasteCurrentClipboardAsPlainText() {
        // Capture destination before reading or rewriting clipboard state.
        let frontmost = NSWorkspace.shared.frontmostApplication
        let destination = frontmost?.processIdentifier == NSRunningApplication.current.processIdentifier
            ? picker.latestExternalApplication : frontmost
        guard let destination, !destination.isTerminated else { return }
        guard let text = PlainTextPastePolicy.text(from: PasteboardSnapshotter.capture(from: .general)) else { return }

        guard PasteboardRestorer.restorePlainText(text) else { return }
        capture.noteOwnWrite()
        guard PasteCommand.ensureEventPostingAccess() else {
            showFeedback("Plain text restored. Paste manually with ⌘V.")
            return
        }

        let destinationPID = destination.processIdentifier
        let alreadyFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == destinationPID
        guard alreadyFrontmost || destination.activate(options: []) else {
            showFeedback("Plain text restored. Destination did not activate; paste manually with ⌘V.")
            return
        }
        waitForDestinationAndPost(destination, attemptsRemaining: 60)
    }

    private func waitForDestinationAndPost(_ destination: NSRunningApplication, attemptsRemaining: Int) {
        let destinationPID = destination.processIdentifier
        guard !destination.isTerminated else {
            showFeedback("Plain text restored. Paste manually with ⌘V.")
            return
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier != destinationPID else {
            if PasteCommand.post(to: destinationPID) { return }
            showFeedback("Plain text restored. Paste manually with ⌘V.")
            return
        }
        guard attemptsRemaining > 0 else {
            showFeedback("Plain text restored. Destination did not activate; paste manually with ⌘V.")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [weak self] in
            self?.waitForDestinationAndPost(destination, attemptsRemaining: attemptsRemaining - 1)
        }
    }

    @objc private func showClipboardReport() {
        let report = PasteboardSnapshotter.capture(from: .general)?.metadataReport
            ?? "No supported clipboard representations are currently available."
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Clipboard Representation Metadata"
        alert.informativeText = "Types and byte counts only. Clipboard payload contents are not displayed or logged."
        alert.addButton(withTitle: "Close")
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 540, height: 280))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let reportView = NSTextView(frame: scroll.bounds)
        reportView.isEditable = false
        reportView.isSelectable = true
        reportView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        reportView.string = report
        scroll.documentView = reportView
        alert.accessoryView = scroll
        alert.runModal()
    }

    private func setManagerActivationPolicy(_ managerIsOpen: Bool) {
        let policy: NSApplication.ActivationPolicy = managerIsOpen ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        _ = NSApp.setActivationPolicy(policy)
        iconController?.scheduleReapplication()
    }

    private func showFeedback(_ message: String) {
        statusItem.button?.title = "✓"
        statusItem.button?.toolTip = message
        feedbackTimer?.invalidate()
        feedbackTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            self?.statusItem.button?.title = ""
            self?.statusItem.button?.toolTip = "The Clipboard · ⌥⌘V"
        }
    }
}
