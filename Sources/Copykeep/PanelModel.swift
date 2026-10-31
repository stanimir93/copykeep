import AppKit
import Combine

enum ClipTab: String, CaseIterable, Identifiable {
    case all = "All", pinned = "Pinned", text = "Text", images = "Images", links = "Links", shortcuts = "Shortcuts"
    var id: Self { self }

    func includes(_ clip: Clip) -> Bool {
        switch self {
        case .all: return true
        case .pinned: return clip.pinned
        case .text: return clip.kind == .text
        case .images: return clip.kind == .image
        case .links: return clip.kind == .link
        case .shortcuts: return false
        }
    }
}

/// The panel's state: search, tab and the selected clip, or the selected text shortcut on the
/// Shortcuts tab.
final class PanelModel: ObservableObject {
    struct Section: Identifiable {
        let id: String
        let title: String?
        let clips: [Clip]
    }

    let history: History
    @Published var query = "" { didSet { if query != oldValue { selectFirst() } } }
    @Published var tab: ClipTab = .all { didSet { if tab != oldValue { selectFirst() } } }
    @Published var selection: UUID?
    /// Set when the selection moved by keyboard, so the list scrolls to it (hovering doesn't).
    @Published var scrollTarget: UUID?
    @Published var trusted = Paster.trusted
    /// "Clear" was clicked once; the second click clears.
    @Published var confirmingClear = false

    weak var field: NSTextField?
    private var lastMouse = NSPoint.zero
    var onPaste: (Clip, _ plain: Bool) -> Void = { _, _ in }
    var onSettings: () -> Void = {}
    /// Opens the shortcut editor, for a new shortcut when nil.
    var onEditShortcut: (TextShortcut?) -> Void = { _ in }
    var onPasteShortcut: (TextShortcut) -> Void = { _ in }
    private var cancellables: [AnyCancellable] = []

    init(history: History) {
        self.history = history
        // Keep the selection on a clip that still exists after the history changes.
        let keepSelection: (Any) -> Void = { [weak self] _ in
            guard let self else { return }
            if let s = self.selection, self.ids.contains(s) { return }
            self.selectFirst()
        }
        cancellables = [
            history.$clips.dropFirst().receive(on: DispatchQueue.main).sink(receiveValue: keepSelection),
            TextShortcuts.shared.$shortcuts.dropFirst().receive(on: DispatchQueue.main).sink(receiveValue: keepSelection),
        ]
    }

    var maskSecrets: Bool { UserDefaults.standard.object(forKey: "maskSecrets") as? Bool ?? true }

    /// With no search on the All tab: Pinned, then Recent. Otherwise one list, pinned first.
    var sections: [Section] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        var list = history.clips.filter(tab.includes)
        if !words.isEmpty {
            list = list.filter { c in
                let hay = c.searchText
                return words.allSatisfy { hay.contains($0) }
            }
        }
        if tab == .all, words.isEmpty {
            let pinned = list.filter(\.pinned)
            let recent = list.filter { !$0.pinned }
            return (pinned.isEmpty ? [] : [Section(id: "pinned", title: "PINNED", clips: pinned)])
                + (recent.isEmpty ? [] : [Section(id: "recent", title: pinned.isEmpty ? nil : "RECENT", clips: recent)])
        }
        let sorted = list.filter(\.pinned) + list.filter { !$0.pinned }
        return sorted.isEmpty ? [] : [Section(id: "results", title: nil, clips: sorted)]
    }

    var ordered: [Clip] { sections.flatMap(\.clips) }
    var selected: Clip? { ordered.first { $0.id == selection } ?? ordered.first }

    /// The Shortcuts tab's list, in the file's order, filtered by the search.
    var shortcuts: [TextShortcut] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        return TextShortcuts.shared.shortcuts.filter { s in words.allSatisfy { s.searchText.contains($0) } }
    }
    var selectedShortcut: TextShortcut? { shortcuts.first { $0.id == selection } ?? shortcuts.first }

    /// The rows the arrow keys move through on this tab.
    var ids: [UUID] { tab == .shortcuts ? shortcuts.map(\.id) : ordered.map(\.id) }

    func selectFirst() {
        selection = ids.first
        scrollTarget = selection
    }

    func move(_ delta: Int) {
        let list = ids
        guard !list.isEmpty else { return }
        let i = list.firstIndex { $0 == selection } ?? -1
        selection = list[max(0, min(list.count - 1, i + delta))]
        scrollTarget = selection
    }

    /// The pointer entered a row. Only a real mouse move selects it: rows scrolling under a
    /// resting pointer while you use the arrow keys don't.
    func hover(_ id: UUID) {
        let mouse = NSEvent.mouseLocation
        guard mouse != lastMouse else { return }
        lastMouse = mouse
        selection = id
    }

    func cycleTab(_ delta: Int) {
        let all = ClipTab.allCases
        let i = all.firstIndex(of: tab) ?? 0
        tab = all[(i + delta + all.count) % all.count]
    }

    /// Called each time the panel opens: a fresh search on the All tab, the newest clip selected.
    func reset() {
        query = ""
        field?.stringValue = ""
        tab = .all
        confirmingClear = false
        trusted = Paster.trusted
        TextShortcuts.shared.reloadIfChanged()
        lastMouse = NSEvent.mouseLocation
        selectFirst()
        objectWillChange.send() // refresh "3 min ago"
    }
}
