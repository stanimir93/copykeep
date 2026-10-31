import AppKit
import SwiftUI

/// The window for making or changing a text shortcut, opened from the panel's Shortcuts tab
/// (⌘N, ⌘E) and from Settings › Shortcuts.
final class ShortcutEditor {
    static let shared = ShortcutEditor()
    private var window: NSWindow?

    /// Opens the editor for `shortcut`, or for a new one when nil.
    func open(_ shortcut: TextShortcut?) {
        let w = window ?? {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.center()
            window = w
            return w
        }()
        w.title = shortcut == nil ? "New Shortcut" : "Edit Shortcut"
        w.contentViewController = NSHostingController(rootView: ShortcutEditorView(original: shortcut) { [weak w] in w?.close() })
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

struct ShortcutEditorView: View {
    let original: TextShortcut?
    let done: () -> Void
    @State private var trigger: String
    @State private var text: String
    @ObservedObject private var store = TextShortcuts.shared

    init(original: TextShortcut?, done: @escaping () -> Void) {
        self.original = original
        self.done = done
        _trigger = State(initialValue: original?.trigger ?? "-")
        _text = State(initialValue: original?.text ?? "")
    }

    private var cleanTrigger: String { trigger.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var clash: Bool { cleanTrigger != original?.trigger && store.shortcut(for: cleanTrigger) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Type") {
                TextField("-email", text: $trigger)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
            }
            Text("Replaced by the text below when you type it in any app, at the start of a word. A sign in front, like -email or ;sig, keeps it from firing in normal writing.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Text").font(.callout)
            TextEditor(text: $text)
                .font(.system(size: 13))
                .frame(minHeight: 110)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
            if clash {
                Text("Replaces the shortcut that already uses \(cleanTrigger).").font(.footnote).foregroundStyle(.orange)
            }
            HStack {
                if let original {
                    Button("Delete", role: .destructive) {
                        store.remove(original.trigger)
                        done()
                    }
                }
                Spacer()
                Button("Cancel", action: done).keyboardShortcut(.cancelAction)
                Button("Save") {
                    store.save(TextShortcut(trigger: cleanTrigger, text: text), replacing: original?.trigger)
                    done()
                }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(cleanTrigger.isEmpty || text.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 400)
    }
}
