import AppKit

enum ClipKind: String, Codable {
    case text, link, image, file
}

/// One thing you copied. The pasteboard data itself (formatting, image bytes) is kept beside
/// the history file, in blobs/<id>.plist; this is what the panel lists and searches.
struct Clip: Codable, Identifiable, Equatable {
    let id: UUID
    var kind: ClipKind
    /// The text, the link, or the file paths one per line. Empty for an image.
    var text: String
    var imageWidth: Int?
    var imageHeight: Int?
    var sourceApp: String?
    var sourceBundleID: String?
    var copiedAt: Date
    var pinned: Bool
    var copyCount: Int
    /// Identifies the content, so copying the same thing again moves it to the top instead of
    /// adding it twice.
    var fingerprint: String

    var fileURLs: [URL] {
        kind == .file ? text.split(separator: "\n").map { URL(fileURLWithPath: String($0)) } : []
    }

    /// Copied from a terminal or a code editor: shown in a monospaced font.
    var isCode: Bool {
        guard let id = sourceBundleID else { return false }
        return Self.codeApps.contains(id) || id.hasPrefix("com.jetbrains.")
    }

    private static let codeApps: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty", "io.alacritty", "com.github.wez.wezterm", "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed", "com.apple.dt.Xcode",
        "com.sublimetext.4", "com.panic.Nova",
    ]

    /// The colour, when the clip is a colour value on its own (`#3b82f6`, `rgb(…)`, `oklch(…)`).
    var color: ColorValue? { kind == .text ? ColorValue.parse(text) : nil }

    /// What the row shows: the first part of the text, with secrets hidden when that's on.
    func preview(maskSecrets: Bool) -> String {
        switch kind {
        case .image:
            return ""
        case .file:
            return fileURLs.map(\.lastPathComponent).joined(separator: ", ")
        case .text, .link:
            let head = String(text.prefix(600)).trimmingCharacters(in: .whitespacesAndNewlines)
            return maskSecrets ? Secrets.mask(head) : head
        }
    }

    /// Lowercased text the search matches against.
    var searchText: String {
        var s = String(text.prefix(5000))
        if let sourceApp { s += " " + sourceApp }
        if kind == .image { s += " image screenshot" }
        if let color { s += " colour color " + color.hex }
        return s.lowercased()
    }
}

/// Hides passwords, API keys and tokens in the list. Only the display: pasting gives the real text.
enum Secrets {
    /// NAME=value or name: value where the name says it's a key, token, secret or password.
    private static let assignment = try! NSRegularExpression(
        pattern: #"(?i)(\b[A-Z0-9_.-]*(?:KEY|TOKEN|SECRET|PASSWORD|PASSWD|PWD)(?:[_.-][A-Z0-9]+)*\b)(\s*[=:]\s*)("[^"\n]+"|'[^'\n]+'|[^\s"']+)"#)
    /// Tokens recognisable by their shape: OpenAI, Stripe, GitHub, Slack, AWS, Google, JWTs.
    private static let tokens = try! NSRegularExpression(
        pattern: #"\b(?:sk-[A-Za-z0-9_-]{16,}|[sr]k_(?:live|test)_[A-Za-z0-9]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[abprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,})"#)
    static let dots = "••••••••"

    static func mask(_ s: String) -> String {
        let range = NSRange(s.startIndex..., in: s)
        var out = assignment.stringByReplacingMatches(in: s, range: range, withTemplate: "$1$2\(dots)")
        out = tokens.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: dots)
        // NAME=value keeps its name; only a bare word is hidden whole.
        return out == s && looksLikePassword(s) ? dots : out
    }

    /// A single word of 12+ characters mixing upper case, lower case and digits, that isn't a
    /// link or a path: most likely a password or a key copied on its own.
    static func looksLikePassword(_ s: String) -> Bool {
        guard (12...200).contains(s.count), !s.contains(where: \.isWhitespace),
              !s.contains("://"), !s.hasPrefix("/"), !s.hasPrefix("~") else { return false }
        return s.contains(where: \.isUppercase) && s.contains(where: \.isLowercase) && s.contains(where: \.isNumber)
    }
}

enum Format {
    /// "just now", "3 min ago", "2 h ago", "Yesterday", "Mon", "20 Oct".
    static func ago(_ date: Date, now: Date = Date()) -> String {
        let s = now.timeIntervalSince(date)
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s / 60)) min ago" }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "\(Int(s / 3600)) h ago" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = s < 6 * 86400 ? "EEE" : (cal.isDate(date, equalTo: now, toGranularity: .year) ? "d MMM" : "d MMM yyyy")
        return f.string(from: date)
    }
}
