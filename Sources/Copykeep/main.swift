import AppKit
import ServiceManagement
import SwiftUI

// Command-line switches; each exits without starting the app.
//   --dump                         print the history as JSON (no clipboard data, only what the panel lists)
//   --snapshot FILE.png [dark] [tab=NAME] [SEARCH]   draw the panel offscreen with the current history
//   --snapshot-settings FILE.png [dark]   draw the Settings window offscreen
//   --expire                       delete the clips past their auto-clear time and print them
//   --register-login-item          turn launch at login on (scripts/install.sh)
//   --unregister-login-item        turn it off
// The login-item switches print the resulting state: enabled, requires-approval, not-registered or not-found.
func loginItemState() -> String {
    switch SMAppService.mainApp.status {
    case .enabled: return "enabled"
    case .requiresApproval: return "requires-approval"
    case .notRegistered: return "not-registered"
    default: return "not-found"
    }
}

/// Copykeep was called Clipboard Shelf. The first launch after the rename moves its history
/// over and copies its settings, except having asked for Accessibility: macOS gives the renamed
/// app its own permission, so it asks again.
func takeOverClipboardShelf() {
    let files = FileManager.default
    let old = History.dir.deletingLastPathComponent().appendingPathComponent("ClipboardShelf")
    if !files.fileExists(atPath: History.dir.path), files.fileExists(atPath: old.path) {
        try? files.moveItem(at: old, to: History.dir)
    }
    let defaults = UserDefaults.standard
    guard !defaults.bool(forKey: "tookOverClipboardShelf") else { return }
    for (key, value) in defaults.persistentDomain(forName: "com.stanimir93.clipboardshelf") ?? [:]
    where key != "askedForAccess" && defaults.object(forKey: key) == nil {
        defaults.set(value, forKey: key)
    }
    defaults.set(true, forKey: "tookOverClipboardShelf")
}
let args = CommandLine.arguments
if args.contains("--dump") {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    FileHandle.standardOutput.write(try! encoder.encode(History().clips))
    print()
    exit(0)
}
if args.contains("--expire") {
    let history = History()
    for clip in AutoClear.shared.expire(history) {
        print("\(clip.sourceApp ?? "?") · \(Format.ago(clip.copiedAt)) · \(clip.kind.rawValue)")
    }
    if let error = AutoClear.shared.error { FileHandle.standardError.write(Data((error + "\n").utf8)) }
    history.waitForWrites()
    exit(0)
}
if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
    _ = NSApplication.shared
    let rest = Array(args.dropFirst(i + 2))
    let dark = rest.first == "dark"
    var words = Array(rest.drop { $0 == "dark" })
    var tab = ClipTab.all
    if let t = words.first, t.hasPrefix("tab=") {
        tab = ClipTab.allCases.first { $0.rawValue.lowercased() == t.dropFirst(4).lowercased() } ?? .all
        words.removeFirst()
    }
    let query = words.joined(separator: " ")
    let history = History()
    let model = PanelModel(history: history)
    model.reset()
    model.trusted = true // the snapshot shows the panel, not this process's Accessibility access
    model.tab = tab
    model.query = query
    let view = NSHostingView(rootView: PanelView(model: model, history: history)
        .background(dark ? Color(white: 0.14) : Color(white: 0.9))) // stands in for the glass, which doesn't draw offscreen
    view.frame = NSRect(origin: .zero, size: PanelView.size)
    let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.contentView = view
    view.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.7))
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
    view.cacheDisplay(in: view.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
    print(args[i + 1])
    exit(0)
}
if let i = args.firstIndex(of: "--snapshot-settings"), i + 1 < args.count {
    _ = NSApplication.shared
    let dark = args.dropFirst(i + 2).first == "dark"
    let view = NSHostingView(rootView: SettingsView(history: History()))
    view.frame = NSRect(origin: .zero, size: view.fittingSize)
    let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.contentView = view
    RunLoop.main.run(until: Date().addingTimeInterval(0.7))
    view.frame.size = view.fittingSize
    view.layoutSubtreeIfNeeded()
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
    view.cacheDisplay(in: view.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
    print(args[i + 1])
    exit(0)
}
if args.contains("--register-login-item") || args.contains("--unregister-login-item") {
    do {
        if args.contains("--register-login-item") {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    } catch {
        FileHandle.standardError.write(Data("login item: \(error.localizedDescription)\n".utf8))
    }
    print(loginItemState())
    exit(0)
}

takeOverClipboardShelf() // not for the switches above, which may run on a made-up history
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
