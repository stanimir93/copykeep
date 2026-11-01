import AppKit
import SwiftUI

/// The shortcuts that start with what you're typing, listed under the text cursor. The app you
/// type in keeps the keyboard: TextExpander passes ↑ ↓ Tab Return and Esc here while it shows.
final class SuggestionModel: ObservableObject {
    @Published var items: [TextShortcut] = []
    @Published var selected = 0
    var onPick: (TextShortcut) -> Void = { _ in }
}

final class SuggestionPopup {
    static let width: CGFloat = 300
    static let rowHeight: CGFloat = 30
    static let maxRows = 6

    let model = SuggestionModel()
    private let panel: NSPanel
    /// Showing, or about to be once the cursor has been found.
    private(set) var isShown = false
    private var placing = 0

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 100),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        let hosting = FirstMouseHostingView(rootView: SuggestionView(model: model))
        let glass = makeGlass(around: hosting, cornerRadius: 12)
        glass.autoresizingMask = [.width, .height]
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.cornerCurve = .continuous
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor(white: 0.5, alpha: 0.3).cgColor
        container.addSubview(glass)
        panel.contentView = container
    }

    var selected: TextShortcut? { model.items.indices.contains(model.selected) ? model.items[model.selected] : nil }

    /// Lists `items`, keeping the selection on the same shortcut when it's still there. The first
    /// time, the list is placed under the text cursor (asked for after this key, so typing isn't
    /// held up), or at the mouse when the app doesn't say where its cursor is.
    func show(_ items: [TextShortcut]) {
        let keep = isShown ? selected?.trigger : nil // a new list starts at the top
        model.items = items
        model.selected = items.firstIndex { $0.trigger == keep } ?? 0
        resize()
        guard !isShown else { return }
        isShown = true
        placing += 1
        let id = placing
        DispatchQueue.main.async { [self] in
            guard isShown, placing == id else { return }
            let anchor = Caret.rect(lastCharacter: true) ?? NSRect(origin: NSEvent.mouseLocation, size: .zero)
            place(under: anchor)
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        panel.orderOut(nil)
    }

    func move(_ delta: Int) {
        guard !model.items.isEmpty else { return }
        model.selected = (model.selected + delta + model.items.count) % model.items.count
    }

    /// The pointer is over the list, so a click there picks a shortcut rather than moving the cursor.
    var containsMouse: Bool { isShown && panel.isVisible && panel.frame.contains(NSEvent.mouseLocation) }

    private var height: CGFloat { CGFloat(min(model.items.count, Self.maxRows)) * Self.rowHeight + 12 + 22 }

    private func resize() {
        var f = panel.frame
        let h = height
        if panel.isVisible, f.height != h {
            if belowCaret { f.origin.y += f.height - h } // keep the top edge under the cursor
            f.size.height = h
            panel.setFrame(f, display: true)
            panel.contentView?.subviews.first?.frame = NSRect(origin: .zero, size: f.size)
        }
    }

    private var belowCaret = true

    private func place(under anchor: NSRect) {
        let size = NSSize(width: Self.width, height: height)
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var y = anchor.minY - 4 - size.height
        belowCaret = y >= area.minY + 8
        if !belowCaret { y = anchor.maxY + 4 }
        let x = min(max(anchor.minX, area.minX + 8), area.maxX - size.width - 8)
        let frame = NSRect(x: x, y: min(max(y, area.minY + 8), area.maxY - size.height - 8), width: size.width, height: size.height)
        panel.setFrame(frame, display: true)
        panel.contentView?.subviews.first?.frame = NSRect(origin: .zero, size: frame.size)
        panel.invalidateShadow()
    }
}

struct SuggestionView: View {
    @ObservedObject var model: SuggestionModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(model.items.enumerated()), id: \.element.trigger) { i, s in
                            row(s, selected: i == model.selected)
                                .id(s.trigger)
                                .contentShape(Rectangle())
                                .onTapGesture { model.onPick(s) }
                        }
                    }
                    .padding(6)
                }
                .scrollIndicators(.never)
                .onChange(of: model.selected) { _, i in
                    if model.items.indices.contains(i) { proxy.scrollTo(model.items[i].trigger) }
                }
            }
            HStack(spacing: 4) {
                hint("⇥"); Text("insert")
                hint("↑↓"); Text("choose")
                hint("esc"); Text("close")
                Spacer()
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 22)
        }
        .background(scheme == .light ? Color(white: 0.9).opacity(0.75) : .clear)
    }

    private func row(_ s: TextShortcut, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label(s.trigger))
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.1)))
            Text(s.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? "")
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(selected ? .primary : .secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: SuggestionPopup.rowHeight)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(selected ? Color.accentColor.opacity(scheme == .light ? 0.2 : 0.35) : .clear))
    }

    /// The trigger without the opening symbol you just typed (§email shows as email).
    private func label(_ trigger: String) -> String {
        let prefix = TextExpander.suggestPrefix
        guard !prefix.isEmpty, trigger.hasPrefix(prefix), trigger.count > prefix.count else { return trigger }
        return String(trigger.dropFirst(prefix.count))
    }

    private func hint(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 9.5, design: .monospaced))
            .padding(.horizontal, 3)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.1)))
    }
}
