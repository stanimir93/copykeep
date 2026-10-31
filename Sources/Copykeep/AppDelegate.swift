import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var history: History!
    private var watcher: ClipboardWatcher!
    private var expander: TextExpander!
    private var panel: PanelController!
    private var settings: SettingsWindowController!
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var expiryTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.editMenu()
        history = History()
        watcher = ClipboardWatcher(history: history)
        watcher.start()
        // Auto-clear: delete clips past their time, now and every 10 s.
        AutoClear.shared.expire(history)
        // Text shortcuts: listens to typing once Accessibility is allowed (checked every 10 s).
        expander = TextExpander(watcher: watcher)
        expander.start()
        let t = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            if let history = self?.history { AutoClear.shared.expire(history) }
            self?.expander.start()
        }
        RunLoop.main.add(t, forMode: .common)
        expiryTimer = t
        settings = SettingsWindowController(history: history)
        panel = PanelController(history: history, watcher: watcher, expander: expander)
        // Typing in Copykeep's own windows (the panel's search, Settings, the shortcut editor)
        // never expands.
        expander.isSuspended = { [weak self] in NSApp.isActive || self?.panel.isShown == true }
        panel.onSettings = { [weak self] in self?.settings.show() }
        HotKey.shared.onPress = { [weak self] in self?.panel.toggleAtCaret() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "Copykeep")
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        menu.delegate = self
        updateIcon()

        // Ask for Accessibility once, on the first launch; Settings and the panel offer it after that.
        if !Paster.trusted, !UserDefaults.standard.bool(forKey: "askedForAccess") {
            UserDefaults.standard.set(true, forKey: "askedForAccess")
            Paster.askForAccess()
        }
    }

    /// Opening the app again from Finder or Spotlight shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        settings.show()
        return false
    }

    /// Left click opens the clipboard under the icon; right click (or ⌃-click) the menu.
    @objc private func statusClicked() {
        guard let button = statusItem.button, let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            statusItem.menu = menu
            button.performClick(nil)
            statusItem.menu = nil
        } else {
            panel.toggle(under: button)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let open = NSMenuItem(title: "Open Clipboard", action: #selector(openPanel), keyEquivalent: "")
        if let s = HotKey.shared.shortcut { open.title += "  \(s.display)" }
        menu.addItem(open)
        let pause = NSMenuItem(title: "Pause Recording", action: #selector(togglePause), keyEquivalent: "")
        pause.state = watcher.paused ? .on : .off
        menu.addItem(pause)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Clear History (keeps pinned)", action: #selector(clearHistory), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Copykeep", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
    }

    @objc private func openPanel() {
        if let button = statusItem.button { panel.toggle(under: button) }
    }

    @objc private func togglePause() {
        watcher.paused.toggle()
        updateIcon()
    }

    @objc private func clearHistory() { history.clearUnpinned() }
    @objc private func openSettings() { settings.show() }

    /// A dimmed icon while recording is paused.
    private func updateIcon() {
        statusItem.button?.appearsDisabled = watcher.paused
        statusItem.button?.toolTip = watcher.paused ? "Copykeep (paused)" : "Copykeep"
    }

    /// An Edit menu, never shown (menu bar app), so ⌘C, ⌘V, ⌘A and ⌘Z work in text fields.
    private static func editMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        appItem.submenu?.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        edit.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        edit.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }
}
