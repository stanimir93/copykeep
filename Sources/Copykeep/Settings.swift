import AppKit
import Carbon.HIToolbox
import Combine
import ServiceManagement
import SwiftUI

/// Settings window, opened from the panel's gear or the menu bar icon's menu. Laid out like
/// System Settings: panes in a sidebar, each one scrolling on its own.
final class SettingsWindowController {
    static let size = NSSize(width: 720, height: 540)
    private let history: History
    private var window: NSWindow?

    init(history: History) { self.history = history }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Copykeep Settings"
            w.isReleasedWhenClosed = false
            w.toolbar = NSToolbar()
            w.toolbarStyle = .unified
            w.contentMinSize = NSSize(width: 620, height: 400)
            w.contentViewController = NSHostingController(rootView: SettingsView(history: history))
            w.setContentSize(Self.size)
            w.center()
            window = w
        }
        // A menu bar app isn't active by default; bring the window to the front.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Launch at login, backed by SMAppService (System Settings › General › Login Items).
final class LoginItem: ObservableObject {
    @Published private(set) var status = SMAppService.mainApp.status
    @Published private(set) var error: String?

    var enabled: Bool { status == .enabled }
    var needsApproval: Bool { status == .requiresApproval }

    func refresh() { status = SMAppService.mainApp.status }

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
    }
}

/// The sidebar's panes, with System Settings-style icons: a white symbol on a coloured square.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General", history = "History", autoClear = "Auto-clear", shortcuts = "Shortcuts"
    var id: Self { self }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .history: return "clock.arrow.circlepath"
        case .autoClear: return "timer"
        case .shortcuts: return "character.cursor.ibeam"
        }
    }

    var color: Color {
        switch self {
        case .general: return .gray
        case .history: return .blue
        case .autoClear: return .orange
        case .shortcuts: return .purple
        }
    }
}

struct SettingsView: View {
    @ObservedObject var history: History
    @AppStorage("settingsPane") private var pane: SettingsPane = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: Binding(get: { pane }, set: { if let p = $0 { pane = p } })) { p in
                Label {
                    Text(p.rawValue)
                } icon: {
                    Image(systemName: p.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(p.color.gradient))
                }
                .tag(p)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            Group {
                switch pane {
                case .general: GeneralPane()
                case .history: HistoryPane(history: history)
                case .autoClear: Form { AutoClearSection(history: history) }.formStyle(.grouped)
                case .shortcuts: Form { ShortcutsSection() }.formStyle(.grouped)
                }
            }
            .navigationTitle(pane.rawValue)
        }
        .frame(minWidth: 620, minHeight: 400)
    }
}

private func note(_ s: String) -> some View {
    Text(s).font(.footnote).foregroundStyle(.secondary)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
}

/// General: the key that opens the clipboard, Accessibility and launch at login.
struct GeneralPane: View {
    @StateObject private var login = LoginItem()
    @ObservedObject private var hotKey = HotKey.shared
    @State private var trusted = Paster.trusted
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                LabeledContent("Open the clipboard") { ShortcutRecorder(hotKey: hotKey) }
                if let error = hotKey.error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("Keyboard")
            } footer: {
                note("Press it in any app to open the clipboard next to the text cursor, and again to close it. To change it, click the button and press the new keys; Esc cancels, Delete removes it.")
            }

            Section {
                LabeledContent("Accessibility") {
                    if trusted {
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Allow…") {
                            Paster.askForAccess()
                            Paster.openAccessibilitySettings()
                        }
                    }
                }
            } header: {
                Text("Pasting")
            } footer: {
                note("Needed to paste into the app you're in, to open next to the text cursor and to expand text shortcuts. Without it, choosing a clip copies it and you press ⌘V yourself.")
            }

            Section {
                Toggle("Open at login", isOn: Binding(get: { login.enabled }, set: { login.set($0) }))
                if login.needsApproval {
                    Button("Approve in Login Items") { SMAppService.openSystemSettingsLoginItems() }
                }
                if let error = login.error { Text(error).font(.footnote).foregroundStyle(.red) }
            } header: {
                Text("Startup")
            }
        }
        .formStyle(.grouped)
        .onReceive(tick) { _ in
            trusted = Paster.trusted
            login.refresh()
        }
    }
}

/// History: how many clips to keep, hiding secrets, and clearing.
struct HistoryPane: View {
    @ObservedObject var history: History
    @AppStorage("maxItems") private var maxItems = 200
    @AppStorage("maskSecrets") private var maskSecrets = true
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section {
                Picker("Keep", selection: $maxItems) {
                    ForEach(History.sizes, id: \.self) { Text("\($0) clips").tag($0) }
                }
                .onChange(of: maxItems) { history.prune() }
                Toggle("Hide passwords and API keys in the list", isOn: $maskSecrets)
                LabeledContent("\(history.clips.count) clips, \(history.clips.filter(\.pinned).count) pinned") {
                    Button(confirmClear ? "Click again to clear" : "Clear History") {
                        if confirmClear { history.clearUnpinned() }
                        confirmClear.toggle()
                    }
                }
            } footer: {
                note("Pinned clips are never removed. Nothing copied in a password manager (1Password, Bitwarden, Passwords, Keychain Access) is kept, nor anything an app marks as concealed, unless an Auto-clear rule covers it. Hidden secrets still paste in full.")
            }
        }
        .formStyle(.grouped)
    }
}

struct ShortcutRecorder: View {
    @ObservedObject var hotKey: HotKey
    @StateObject private var recorder = KeyRecorder()

    var body: some View {
        HStack(spacing: 6) {
            Button(recorder.recording ? "Press the keys…" : hotKey.shortcut?.display ?? "Record Shortcut") {
                recorder.recording ? recorder.stop() : recorder.start(hotKey)
            }
            if hotKey.shortcut != nil, !recorder.recording {
                Button {
                    hotKey.set(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove the shortcut")
            }
        }
        .onDisappear { recorder.stop() }
    }
}

final class KeyRecorder: ObservableObject {
    @Published private(set) var recording = false
    private var monitor: Any?
    private var hotKey: HotKey?

    func start(_ hotKey: HotKey) {
        self.hotKey = hotKey
        hotKey.pause() // so pressing the current shortcut records it instead of opening the panel
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            let plain = e.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
            if plain, e.keyCode == UInt16(kVK_Escape) {
                self?.stop()
            } else if plain, e.keyCode == UInt16(kVK_Delete) {
                hotKey.set(nil)
                self?.stop()
            } else if let shortcut = Shortcut(event: e) {
                hotKey.set(shortcut)
                self?.stop()
            }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { hotKey?.resume() }
        recording = false
    }
}

/// Settings › Auto-clear: a time for every clip (off by default), one row per app with its time,
/// and a menu to add an app.
struct AutoClearSection: View {
    @ObservedObject var history: History
    @ObservedObject private var autoClear = AutoClear.shared

    var body: some View {
        Section {
            Picker("All clips", selection: Binding(get: { autoClear.allClips ?? 0 }, set: { autoClear.setAllClips($0) })) {
                Text("Never").tag(0)
                ForEach(Set(AutoClear.choices + [autoClear.allClips ?? 1440]).sorted(), id: \.self) { m in
                    Text("after \(AutoClear.label(m))").tag(m)
                }
            }
            ForEach(autoClear.rules) { rule in
                HStack(spacing: 8) {
                    AppIcon(app: rule.app)
                    Picker(rule.name, selection: Binding(get: { rule.minutes }, set: { m in
                        var r = rule
                        r.minutes = m
                        autoClear.set(r)
                    })) {
                        ForEach(Set(AutoClear.choices + [rule.minutes]).sorted(), id: \.self) { m in
                            Text("after \(AutoClear.label(m))").tag(m)
                        }
                    }
                    Button {
                        autoClear.remove(rule.app)
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Stop clearing \(rule.name)")
                }
            }
            Menu("Add App…") {
                ForEach(addable, id: \.app) { item in
                    Button(item.name) { autoClear.set(AutoClearRule(app: item.app, name: item.name, minutes: 15)) }
                }
                Divider()
                Button("Other App…", action: chooseApp)
            }
            .fixedSize()
            if let error = autoClear.error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("All clips, or clips copied from these apps, are deleted after the time you choose, counted from the last copy or paste, and taken off the clipboard if they're still on it. When both apply, the shorter time wins. Pinned clips stay. Bitwarden (browser extension) covers copies made in its popup or web vault in Chrome, Edge, Brave, Zen, Firefox and Safari.")
                HStack(spacing: 4) {
                    Text("Saved in ~/.config/copykeep/auto-clear.json")
                    Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([AutoClear.fileURL]) }
                        .buttonStyle(.link)
                        .disabled(!FileManager.default.fileExists(atPath: AutoClear.fileURL.path))
                }
            }
            .font(.footnote).foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { autoClear.reloadIfChanged() }
    }

    /// Bitwarden's extension, the password managers that are installed, then the apps in the
    /// history, leaving out the ones that already have a rule.
    private var addable: [(app: String, name: String)] {
        var items = BrowserExtensions.known.map { ($0.app, $0.name) }
        for id in ClipboardWatcher.ignoredApps.sorted() {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                items.append((id, FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")))
            }
        }
        var seen = Set(items.map(\.0))
        for clip in history.clips {
            guard let id = clip.sourceBundleID, let name = clip.sourceApp, !seen.contains(id) else { continue }
            seen.insert(id)
            items.append((id, name))
        }
        let taken = autoClear.apps
        return items.filter { !taken.contains($0.0) }.map { (app: $0.0, name: $0.1) }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        autoClear.set(AutoClearRule(app: id, name: name, minutes: 15))
    }
}

/// Settings › Shortcuts: typing a trigger in any app puts in its text.
struct ShortcutsSection: View {
    @ObservedObject private var store = TextShortcuts.shared
    @AppStorage("expandShortcuts") private var expand = true

    var body: some View {
        Section {
            Toggle("Expand shortcuts as you type", isOn: $expand)
        }
        Section {
            ForEach(store.shortcuts) { s in
                HStack(spacing: 8) {
                    Text(s.trigger).font(.system(.body, design: .monospaced))
                    Text(s.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? "")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        ShortcutEditor.shared.open(s)
                    } label: {
                        Image(systemName: "pencil.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Edit \(s.trigger)")
                    Button {
                        store.remove(s.trigger)
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete \(s.trigger)")
                }
            }
            Button("Add Shortcut…") { ShortcutEditor.shared.open(nil) }
            if let error = store.error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Type a shortcut such as -email and a space, at the start of a word in any app, and it's replaced with its text. The panel's Shortcuts tab lists them too. Needs Accessibility, like pasting.")
                HStack(spacing: 4) {
                    Text("Saved in ~/.config/copykeep/shortcuts.json")
                    Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([TextShortcuts.fileURL]) }
                        .buttonStyle(.link)
                        .disabled(!FileManager.default.fileExists(atPath: TextShortcuts.fileURL.path))
                }
            }
            .font(.footnote).foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { store.reloadIfChanged() }
    }
}

private struct AppIcon: View {
    let app: String
    var body: some View {
        Group {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
            } else {
                Image(systemName: app.hasPrefix("browser-extension:") ? "puzzlepiece.extension" : "app.dashed")
                    .resizable().scaledToFit().foregroundStyle(.secondary).padding(1)
            }
        }
        .frame(width: 18, height: 18)
    }
}
