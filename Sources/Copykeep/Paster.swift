import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Puts a clip back on the clipboard and presses ⌘V in the app you're in. Pressing keys for
/// another app needs Accessibility access; without it the clip is only copied.
enum Paster {
    static var trusted: Bool { AXIsProcessTrusted() }

    /// Shows macOS's "Copykeep would like to control this computer" prompt.
    static func askForAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// Writes the clip to the clipboard: every format it was copied with, or only its text when
    /// `plain` (formatting dropped).
    static func write(_ clip: Clip, reps: Reps?, plain: Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if plain, clip.kind == .text || clip.kind == .link {
            pb.setString(clip.text, forType: .string)
            return
        }
        guard let reps, !reps.isEmpty else {
            pb.setString(clip.text, forType: .string)
            return
        }
        let items = reps.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: NSPasteboard.PasteboardType(type)) }
            // Images are kept as PNG only; some apps still want TIFF.
            if clip.kind == .image, dict["public.tiff"] == nil, let png = dict["public.png"],
               let tiff = NSImage(data: png)?.tiffRepresentation {
                item.setData(tiff, forType: .tiff)
            }
            return item
        }
        pb.writeObjects(items)
    }

    /// Presses ⌘V. Uses the V key's position on a US keyboard, which is what ⌘ shortcuts follow
    /// on most layouts, Cyrillic ones included.
    static func pressCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        // Keys still held from the shortcut (⌥) must not reach the app with the V.
        src?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents],
                                                        state: .eventSuppressionStateSuppressionInterval)
        let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }
}

/// Where the text cursor is in the app you're in, through the Accessibility API, so the panel
/// opens beside it like Windows' clipboard does.
enum Caret {
    /// The caret's rectangle in screen coordinates (origin bottom left), or nil when the app
    /// doesn't say: no Accessibility access, no text field focused, or an app that doesn't
    /// report it (some Electron apps).
    /// `lastCharacter` measures the character before the cursor instead, which some apps
    /// (TextEdit) report more exactly than the empty cursor: it's what the suggestions sit under.
    static func rect(lastCharacter: Bool = false) -> NSRect? {
        guard Paster.trusted else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement

        var range: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success, var range {
            var r = CFRange()
            if lastCharacter, CFGetTypeID(range) == AXValueGetTypeID(), AXValueGetValue(range as! AXValue, .cfRange, &r),
               r.location > 0 {
                var before = CFRange(location: r.location - 1, length: 1)
                if let value = AXValueCreate(.cfRange, &before) { range = value }
            }
            var bounds: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                          range, &bounds) == .success,
               let r = cgRect(bounds), r.height > 0, r.origin != .zero {
                return flip(r)
            }
        }
        // No caret position: use the field itself when it's a one-line field, not a whole page.
        var pos: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &pos) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let p = cgPoint(pos), let s = cgSize(size),
              s.height > 0, s.height < 60 else { return nil }
        return flip(CGRect(origin: p, size: s))
    }

    private static func cgRect(_ value: CFTypeRef?) -> CGRect? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var r = CGRect.zero
        return AXValueGetValue(value as! AXValue, .cgRect, &r) ? r : nil
    }

    private static func cgPoint(_ value: CFTypeRef?) -> CGPoint? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &p) ? p : nil
    }

    private static func cgSize(_ value: CFTypeRef?) -> CGSize? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &s) ? s : nil
    }

    /// Accessibility measures from the top of the main screen; AppKit from the bottom.
    private static func flip(_ r: CGRect) -> NSRect {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return NSRect(x: r.minX, y: top - r.maxY, width: r.width, height: r.height)
    }
}
