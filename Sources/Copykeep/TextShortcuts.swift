import AppKit
import Carbon.HIToolbox
import CryptoKit

/// A text shortcut: typing `trigger` in any app replaces it with `text`.
struct TextShortcut: Codable, Equatable, Identifiable {
    var trigger: String
    var text: String

    /// Stable for a trigger, so the panel keeps its selection when the file is read again.
    var id: UUID {
        let bytes = Array(SHA256.hash(data: Data(("shortcut:" + trigger).utf8)))
        return bytes.withUnsafeBufferPointer { NSUUID(uuidBytes: $0.baseAddress) as UUID }
    }

    var searchText: String { (trigger + " " + text).lowercased() }
}

/// The text shortcuts, kept in ~/.config/copykeep/shortcuts.json so they're easy to edit by hand
/// or by an agent. Settings and the panel read and write the same file; edits made elsewhere are
/// picked up within a second of typing, or when the panel or Settings opens:
///
///     {"shortcuts": [{"trigger": "-email", "text": "me@example.com"}]}
final class TextShortcuts: ObservableObject {
    static let shared = TextShortcuts()
    static let fileURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/copykeep/shortcuts.json")

    @Published private(set) var shortcuts: [TextShortcut] = []
    /// Set when the file can't be read; the shortcuts read before stay in use.
    @Published private(set) var error: String?
    private var loadedDate: Date?
    private var checkedAt = Date.distantPast

    private init() { reload() }

    func shortcut(for trigger: String) -> TextShortcut? { shortcuts.first { $0.trigger == trigger } }

    /// Adds `shortcut`, or replaces the one with the trigger `old` (renaming it). Another
    /// shortcut that already has the new trigger is replaced too.
    func save(_ shortcut: TextShortcut, replacing old: String? = nil) {
        var list = shortcuts
        let at = list.firstIndex { $0.trigger == (old ?? shortcut.trigger) } ?? list.firstIndex { $0.trigger == shortcut.trigger }
        list.removeAll { $0.trigger == shortcut.trigger || $0.trigger == old }
        list.insert(shortcut, at: min(at ?? list.count, list.count))
        shortcuts = list
        write()
    }

    func remove(_ trigger: String) {
        shortcuts.removeAll { $0.trigger == trigger }
        write()
    }

    /// The shortcut whose trigger `typed` ends with, at the start of a word: after a space,
    /// punctuation or nothing, so "-email" fires but "re-email" doesn't. The longest wins.
    func match(_ typed: String) -> TextShortcut? {
        shortcuts.filter { !$0.trigger.isEmpty && typed.hasSuffix($0.trigger) }
            .sorted { $0.trigger.count > $1.trigger.count }
            .first { s in
                guard let before = typed.dropLast(s.trigger.count).last else { return true }
                return !(before.isLetter || before.isNumber)
            }
    }

    /// Reads the file again when it changed since the last read.
    func reloadIfChanged() {
        checkedAt = Date()
        if Self.modified() != loadedDate { reload() }
    }

    /// Like reloadIfChanged, at most once a second (called while you type).
    func reloadIfStale() {
        if Date().timeIntervalSince(checkedAt) > 1 { reloadIfChanged() }
    }

    private struct File: Codable {
        var shortcuts: [TextShortcut]
    }

    private func reload() {
        loadedDate = Self.modified()
        guard let data = try? Data(contentsOf: Self.fileURL) else {
            shortcuts = []
            error = nil
            return
        }
        do {
            let file = try JSONDecoder().decode(File.self, from: data)
            var seen = Set<String>()
            shortcuts = file.shortcuts.filter { !$0.trigger.isEmpty && seen.insert($0.trigger).inserted }
            error = nil
        } catch {
            self.error = "\(Self.fileURL.lastPathComponent) can't be read, so the shortcuts from before stay in use: \(error.localizedDescription)"
        }
    }

    private func write() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(File(shortcuts: shortcuts)) else { return }
        try? FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.fileURL, options: .atomic)
        loadedDate = Self.modified()
        error = nil
    }

    private static func modified() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }
}

/// Watches what you type in every app and, when it ends with a shortcut's trigger, deletes the
/// trigger and pastes the shortcut's text. The paste goes through the clipboard, which gets its
/// old contents back afterwards. Reading keys and pressing them for another app needs
/// Accessibility access; until it's allowed, nothing is expanded.
final class TextExpander {
    private let watcher: ClipboardWatcher
    private var tap: CFMachPort?
    /// What was typed since the last click, app switch or non-typing key.
    private var typed = ""
    /// The shortcut being put in. Until its paste has gone through, keys typed after the trigger
    /// (fast typing, or keys a script sends) are held back, then let through in order.
    private var pending: TextShortcut?
    private var held: [CGEvent] = []
    /// The keys whose key-down is held back, so their key-up waits too. (Other key-ups go
    /// through: holding the trigger's last key-up makes the next press of that key go missing.)
    private var heldKeys: Set<Int64> = []
    /// What the clipboard held before the last shortcut went in, and how to tell it's still ours.
    private var restore: (saved: Reps, changeCount: Int)?
    private var expansion = 0
    /// True while Copykeep's own windows take the keys (the panel, Settings, the editor).
    var isSuspended: () -> Bool = { false }

    /// Marks the keys Copykeep presses itself, so they aren't read as typing.
    private static let marker: Int64 = 0x436B_6B70
    static var enabled: Bool { UserDefaults.standard.object(forKey: "expandShortcuts") as? Bool ?? true }

    init(watcher: ClipboardWatcher) {
        self.watcher = watcher
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] _ in self?.typed = "" }
    }

    /// Starts watching the keyboard once Accessibility is allowed; call again later when it isn't yet.
    /// An active tap rather than a listening one: a listening tap hears keys only after the app
    /// got them, so it can't hold back the ones typed while a shortcut is put in.
    func start() {
        guard tap == nil, Paster.trusted else { return }
        let mask = [CGEventType.keyDown, .keyUp, .leftMouseDown, .rightMouseDown, .otherMouseDown]
            .reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let expander = Unmanaged<TextExpander>.fromOpaque(refcon).takeUnretainedValue()
            return expander.handle(type, event) ? Unmanaged.passUnretained(event) : nil
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        self.tap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// Returns false to hold the event back.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        case .keyDown, .keyUp:
            break
        default: // a click moves the text cursor
            if pending == nil { typed = "" }
            return true
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.marker {
            // Copykeep's own ⌘V has gone by: the keys held back can follow it.
            if type == .keyUp, pending != nil, event.flags.contains(.maskCommand),
               event.getIntegerValueField(.keyboardEventKeycode) == kVK_ANSI_V {
                release()
            }
            return true
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if pending != nil, type == .keyDown || heldKeys.contains(code), let copy = event.copy() {
            if type == .keyDown { heldKeys.insert(code) }
            held.append(copy)
            return false
        }
        guard type == .keyDown else { return true }
        guard Self.enabled, !isSuspended(), let key = Self.typedKey(event) else {
            // A shortcut key, Return, an arrow…: the text cursor may have moved, so start over.
            typed = ""
            return true
        }
        switch key {
        case .delete:
            if !typed.isEmpty { typed.removeLast() }
            return true
        case .text(let s):
            typed = String((typed + s).suffix(100))
        }
        TextShortcuts.shared.reloadIfStale()
        guard let match = TextShortcuts.shared.match(typed) else { return true }
        typed = ""
        pending = match
        expansion += 1
        let id = expansion
        // This key goes through first, so the whole trigger is there to delete.
        DispatchQueue.main.async { self.insert(match.text, deleting: match.trigger.count) }
        // In case the ⌘V is never seen coming back, don't hold the keyboard for long.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { if self.expansion == id { self.release() } }
        return true
    }

    /// Lets the keys held back during an expansion through, in the order they were typed.
    private func release() {
        expansion += 1
        pending = nil
        let events = held
        held = []
        heldKeys = []
        for e in events {
            e.setIntegerValueField(.eventSourceUserData, value: Self.marker)
            e.post(tap: .cgSessionEventTap)
        }
    }

    private enum TypedKey {
        case text(String), delete
    }

    /// The text a key types, or Delete; nil for keys that don't type (with ⌘ or ⌃, Return, Tab,
    /// Esc, arrows and function keys: control and private-use characters).
    private static func typedKey(_ event: CGEvent) -> TypedKey? {
        guard event.flags.intersection([.maskCommand, .maskControl]).isEmpty else { return nil }
        if event.getIntegerValueField(.keyboardEventKeycode) == kVK_Delete { return .delete }
        var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: chars.count, actualStringLength: &length, unicodeString: &chars)
        let s = String(utf16CodeUnits: chars, count: length)
        guard !s.isEmpty, !s.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F || (0xF700...0xF8FF).contains($0.value) }) else {
            return nil
        }
        return .text(s)
    }

    /// Presses Delete `count` times, then pastes `text`, and puts the clipboard back as it was.
    /// Without Accessibility the text is only copied, for you to paste.
    func insert(_ text: String, deleting count: Int = 0) {
        let pb = NSPasteboard.general
        // Right after another shortcut, the clipboard still holds that one's text: keep what
        // was there before it instead.
        let saved: Reps = restore.flatMap { $0.changeCount == pb.changeCount ? $0.saved : nil } ?? (pb.pasteboardItems ?? []).map { item in
            var dict: [String: Data] = [:]
            for t in item.types where ClipboardWatcher.keptTypes.contains(t.rawValue) { dict[t.rawValue] = item.data(forType: t) }
            return dict
        }.filter { !$0.isEmpty }

        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        guard Paster.trusted else {
            pb.writeObjects([item])
            return
        }
        // Other clipboard managers leave a transient copy alone; Copykeep skips it below.
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        pb.writeObjects([item])
        watcher.skipCurrent()
        let ours = pb.changeCount
        restore = (saved, ours)

        let src = CGEventSource(stateID: .hidSystemState)
        for _ in 0..<count { press(CGKeyCode(kVK_Delete), flags: [], source: src) }
        press(CGKeyCode(kVK_ANSI_V), flags: .maskCommand, source: src)

        // Give the app time to read the clipboard, then put back what was there, unless
        // something else has been copied meanwhile.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard pb.changeCount == ours else { return }
            pb.clearContents()
            if !saved.isEmpty {
                pb.writeObjects(saved.map { dict in
                    let item = NSPasteboardItem()
                    for (type, data) in dict { item.setData(data, forType: NSPasteboard.PasteboardType(type)) }
                    return item
                })
            }
            self?.watcher.skipCurrent()
            self?.restore = nil
        }
    }

    private func press(_ key: CGKeyCode, flags: CGEventFlags, source: CGEventSource?) {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { continue }
            e.flags = flags
            e.setIntegerValueField(.eventSourceUserData, value: Self.marker)
            e.post(tap: .cgSessionEventTap)
        }
    }
}
