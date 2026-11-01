import AppKit
import SwiftUI

/// The popup: search field, tabs, the clips, and a line of key hints.
struct PanelView: View {
    static let size = CGSize(width: 340, height: 470)
    static let cornerRadius: CGFloat = 20

    @ObservedObject var model: PanelModel
    @ObservedObject var history: History
    @ObservedObject private var store = TextShortcuts.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            SearchField(model: model)
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 6)
            tabs
            if !model.trusted { accessBanner }
            if model.tab == .shortcuts { shortcutList } else { list }
            Divider().opacity(0.6)
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        // The glass alone comes out near white in light mode; a grey wash keeps the white
        // cards and the pale blue selection readable on it.
        .background(scheme == .light ? Color(white: 0.9).opacity(0.75) : .clear)
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(ClipTab.allCases) { t in
                Button {
                    model.tab = t
                } label: {
                    HStack(spacing: 3) {
                        if t == .pinned { Image(systemName: "pin.fill").font(.system(size: 9)) }
                        Text(t.rawValue)
                    }
                    .font(.system(size: 11.5, weight: model.tab == t ? .semibold : .regular))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(model.tab == t ? Color.primary.opacity(scheme == .light ? 0.085 : 0.12) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.tab == t ? .primary : .secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private var accessBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
            Text("Allow Accessibility so ↩ pastes. For now it only copies.")
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Allow") {
                Paster.askForAccess()
                Paster.openAccessibilitySettings()
            }
            .controlSize(.small)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private func empty(_ symbol: String, button: Bool = false) -> some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: model.query.isEmpty ? symbol : "magnifyingglass")
                .font(.system(size: 26)).foregroundStyle(.tertiary)
            Text(emptyText).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if button {
                Button("New Shortcut") { model.onEditShortcut(nil) }.controlSize(.small).padding(.top, 4)
            }
            Spacer()
        }
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var shortcutList: some View {
        let shortcuts = model.shortcuts
        let selectedID = model.selection ?? shortcuts.first?.id
        if shortcuts.isEmpty {
            empty("text.badge.plus", button: model.query.isEmpty)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(shortcuts) { s in
                            ShortcutRow(shortcut: s, selected: s.id == selectedID,
                                        onPaste: { model.onPasteShortcut(s) },
                                        onHover: { model.hover(s.id) },
                                        onEdit: { model.onEditShortcut(s) },
                                        onDelete: { store.remove(s.trigger) })
                                .id(s.id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
                .onChange(of: model.scrollTarget) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
        }
    }

    @ViewBuilder private var list: some View {
        let sections = model.sections
        let selectedID = model.selection ?? sections.first?.clips.first?.id
        if sections.isEmpty {
            empty("doc.on.clipboard")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(sections) { section in
                            if let title = section.title {
                                Text(title)
                                    .font(.system(size: 9.5, weight: .medium))
                                    .tracking(0.6)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 2)
                                    .padding(.top, section.id == sections.first?.id ? 0 : 4)
                            }
                            ForEach(section.clips) { clip in
                                ClipRow(clip: clip, selected: clip.id == selectedID,
                                        thumbnail: clip.kind == .image ? history.thumbnail(clip.id) : nil,
                                        maskSecrets: model.maskSecrets,
                                        onPaste: { model.onPaste(clip, false) },
                                        onHover: { model.hover(clip.id) },
                                        onPin: { history.togglePin(clip.id) },
                                        onDelete: { history.delete(clip.id) })
                                    .id(clip.id)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
                .onChange(of: model.scrollTarget) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
        }
    }

    private var emptyText: String {
        if !model.query.isEmpty { return "Nothing matches “\(model.query)”." }
        switch model.tab {
        case .pinned: return "Nothing pinned yet. Select a clip and press ⌘P to keep it here."
        case .all: return "Nothing copied yet. Copy something and it shows up here."
        case .shortcuts: return "No shortcuts yet. Make one like -email, and typing it and a space in any app puts in your email address."
        default: return "No \(model.tab.rawValue.lowercased()) copied yet."
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Group {
                if model.tab == .shortcuts {
                    Key("↩"); Text("paste")
                    Key("⌘N"); Text("new")
                    Key("⌘E"); Text("edit")
                } else {
                    Key("↩"); Text("paste")
                    Key("⇧↩"); Text("plain")
                    Key("⌘P"); Text("pin")
                }
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if model.tab == .shortcuts {
                Button("New") { model.onEditShortcut(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .help("Make a text shortcut (⌘N)")
            } else {
                clearButton
            }
            Button {
                model.onSettings()
            } label: {
                Image(systemName: "gearshape").font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings")
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
    }

    private var clearButton: some View {
        Button(model.confirmingClear ? "Clear all?" : "Clear") {
            if model.confirmingClear {
                history.clearUnpinned()
                model.confirmingClear = false
            } else {
                model.confirmingClear = true
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: model.confirmingClear ? .semibold : .regular))
        .foregroundStyle(model.confirmingClear ? Color.red : Color.secondary)
        .help("Removes everything except pinned clips")
    }
}

private struct Key: View {
    let label: String
    init(_ label: String) { self.label = label }
    var body: some View {
        Text(label)
            .font(.system(size: 10, design: .monospaced))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.1)))
    }
}

struct ClipRow: View {
    let clip: Clip
    let selected: Bool
    let thumbnail: NSImage?
    let maskSecrets: Bool
    let onPaste: () -> Void
    let onHover: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if clip.kind == .image {
                // The picture fills the card edge to edge; only the line under it is inset.
                image
                metaLine.padding(.horizontal, 10).padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    content
                    metaLine
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
        .card(selected: selected)
        .overlay(alignment: .topTrailing) {
            if hovered {
                HStack(spacing: 2) {
                    CardButton(symbol: clip.pinned ? "pin.slash" : "pin", help: clip.pinned ? "Unpin (⌘P)" : "Pin (⌘P)", action: onPin)
                    CardButton(symbol: "trash", help: "Delete (⌘⌫)", action: onDelete)
                }
                .padding(5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onPaste)
        .onHover { inside in
            hovered = inside
            if inside { onHover() }
        }
    }

    private var metaLine: some View {
        HStack(spacing: 4) {
            if clip.pinned { Image(systemName: "pin.fill").font(.system(size: 8)) }
            Text(meta).lineLimit(1)
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder private var image: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: 90)
                .clipped()
        } else {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 90)
                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
        }
    }

    @ViewBuilder private var content: some View {
        switch clip.kind {
        case .image:
            image
        case .file:
            HStack(spacing: 6) {
                if let first = clip.fileURLs.first {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: first.path)).resizable().frame(width: 18, height: 18)
                }
                Text(clip.preview(maskSecrets: maskSecrets)).lineLimit(2).font(.system(size: 12))
            }
            .foregroundStyle(.primary)
        case .text, .link:
            if let color = clip.color {
                HStack(spacing: 8) {
                    ColorSwatch(color: color)
                    Text(clip.preview(maskSecrets: false))
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                }
            } else {
                Text(clip.preview(maskSecrets: maskSecrets))
                    .font(clip.isCode ? .system(size: 11, design: .monospaced) : .system(size: 12))
                    .lineLimit(clip.kind == .link ? 2 : 3)
                    .truncationMode(clip.kind == .link ? .middle : .tail)
                    .foregroundStyle(.primary)
            }
        }
    }

    private var meta: String {
        var parts: [String] = []
        if let app = clip.sourceApp { parts.append(app) }
        if clip.kind == .image, let w = clip.imageWidth, let h = clip.imageHeight { parts.append("\(w)×\(h)") }
        if clip.kind == .file, clip.fileURLs.count > 1 { parts.append("\(clip.fileURLs.count) files") }
        // A colour written another way also shows its hex.
        if let color = clip.color, !clip.text.uppercased().contains(color.hex) { parts.append(color.hex) }
        parts.append(Format.ago(clip.copiedAt))
        return parts.joined(separator: " · ")
    }
}

/// The colour a clip holds, over a checkerboard so a see-through colour reads as one.
private struct ColorSwatch: View {
    let color: ColorValue
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        ZStack {
            if color.alpha < 1 {
                Canvas { ctx, size in
                    let cell: CGFloat = 5
                    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                    for row in 0..<Int(ceil(size.height / cell)) {
                        for col in 0..<Int(ceil(size.width / cell)) where (row + col).isMultiple(of: 2) {
                            ctx.fill(Path(CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)),
                                     with: .color(Color(white: 0.8)))
                        }
                    }
                }
            }
            Color(nsColor: color.nsColor)
        }
        .frame(width: 26, height: 26)
        .clipShape(shape)
        .overlay(shape.strokeBorder(scheme == .light ? Color.black.opacity(0.15) : Color.white.opacity(0.2), lineWidth: 0.5))
    }
}

/// A text shortcut in the Shortcuts tab: its text, and the trigger that types it.
struct ShortcutRow: View {
    let shortcut: TextShortcut
    let selected: Bool
    let onPaste: () -> Void
    let onHover: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(shortcut.text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 12))
                .lineLimit(3)
                .foregroundStyle(.primary)
            HStack(spacing: 4) {
                Text(shortcut.trigger)
                    .font(.system(size: 10, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.1)))
                Text("types this").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(selected: selected)
        .overlay(alignment: .topTrailing) {
            if hovered {
                HStack(spacing: 2) {
                    CardButton(symbol: "pencil", help: "Edit (⌘E)", action: onEdit)
                    CardButton(symbol: "trash", help: "Delete (⌘⌫)", action: onDelete)
                }
                .padding(5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onPaste)
        .onHover { inside in
            hovered = inside
            if inside { onHover() }
        }
    }
}

/// A row's card: like System Settings' grouped boxes, a hairline edge and a soft shadow, so each
/// row stands apart from the glass and from the next one.
private struct Card: ViewModifier {
    let selected: Bool
    @Environment(\.colorScheme) private var scheme
    private static let radius: CGFloat = 12

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        content
            .background {
                ZStack {
                    fill
                    if selected { selectedTint }
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(edge, lineWidth: selected ? 1.5 : 0.5))
            .shadow(color: .black.opacity(scheme == .light ? 0.08 : 0.3), radius: 3, y: 1)
    }

    /// Near-solid white on the grey-tinted glass in light mode, a clear lift in dark mode.
    private var fill: Color { scheme == .light ? Color.white.opacity(0.92) : Color.white.opacity(0.1) }
    /// The selection is a light wash of the accent colour, not the full-strength fill.
    private var selectedTint: Color { Color.accentColor.opacity(scheme == .light ? 0.2 : 0.35) }
    private var edge: Color {
        if selected { return Color.accentColor.opacity(scheme == .light ? 0.55 : 0.7) }
        return scheme == .light ? Color.black.opacity(0.1) : Color.white.opacity(0.1)
    }
}

extension View {
    fileprivate func card(selected: Bool) -> some View { modifier(Card(selected: selected)) }
}

/// The small round buttons shown on a hovered row.
private struct CardButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5))
                .frame(width: 20, height: 20)
                .background(Circle().fill(.regularMaterial))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .help(help)
    }
}

/// The search field, an AppKit text field so the panel can focus it the moment it opens.
struct SearchField: NSViewRepresentable {
    @ObservedObject var model: PanelModel

    func makeNSView(context: Context) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 16 // a capsule, like System Settings' search field
        box.layer?.borderWidth = 3

        let icon = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)!)
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.placeholderString = "Search clipboard"
        field.delegate = context.coordinator
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.translatesAutoresizingMaskIntoConstraints = false

        let count = NSTextField(labelWithString: "")
        count.font = .systemFont(ofSize: 10.5)
        count.textColor = .secondaryLabelColor
        count.translatesAutoresizingMaskIntoConstraints = false
        count.setContentHuggingPriority(.required, for: .horizontal)
        count.setContentCompressionResistancePriority(.required, for: .horizontal)

        box.addSubview(icon)
        box.addSubview(field)
        box.addSubview(count)
        NSLayoutConstraint.activate([
            box.heightAnchor.constraint(equalToConstant: 32),
            icon.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            field.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            field.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            count.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: 6),
            count.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
            count.centerYAnchor.constraint(equalTo: box.centerYAnchor),
        ])
        context.coordinator.count = count
        context.coordinator.box = box
        model.field = field
        return box
    }

    func updateNSView(_ box: NSView, context: Context) {
        if let field = model.field {
            if field.stringValue != model.query { field.stringValue = model.query }
            field.placeholderString = model.tab == .shortcuts ? "Search shortcuts" : "Search clipboard"
        }
        let searching = !model.query.isEmpty
        let n = model.ordered.count
        context.coordinator.count?.stringValue = searching ? (n == 1 ? "1 result" : "\(n) results") : ""
        let light = box.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
        box.effectiveAppearance.performAsCurrentDrawingAppearance {
            box.layer?.backgroundColor = (light ? NSColor.white.withAlphaComponent(0.6) : NSColor.labelColor.withAlphaComponent(0.06)).cgColor
            // A soft light-blue focus band, like the search fields in macOS 26.
            box.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(light ? 0.25 : 0.35).cgColor
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: PanelModel
        weak var count: NSTextField?
        weak var box: NSView?
        init(model: PanelModel) { self.model = model }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            model.query = field.stringValue
        }
    }
}
