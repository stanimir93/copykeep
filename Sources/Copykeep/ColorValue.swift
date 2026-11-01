import AppKit

/// A colour value copied on its own, such as `#3b82f6`, `rgb(59 130 246)`, `hsl(217 91% 60%)`
/// or `oklch(62% 0.19 260)`. The row shows a swatch of it.
struct ColorValue: Equatable {
    /// sRGB components; the lab and oklch spaces can give values outside 0...1 (wide gamut).
    var red: Double, green: Double, blue: Double
    var alpha: Double

    var nsColor: NSColor {
        NSColor(colorSpace: .extendedSRGB, components: [red, green, blue, alpha].map { CGFloat($0) }, count: 4)
    }

    /// `#RRGGBB`, or `#RRGGBBAA` when it's see-through. Out-of-gamut colours are clipped.
    var hex: String {
        let parts = alpha < 1 ? [red, green, blue, alpha] : [red, green, blue]
        return "#" + parts.map { String(format: "%02X", Int((min(max($0, 0), 1) * 255).rounded())) }.joined()
    }

    /// The colour in `text`, when the text is nothing but a colour. A CSS declaration around it
    /// (`--brand: #ff0;`, `color: red !important`) is allowed; a sentence that mentions one isn't.
    static func parse(_ text: String) -> ColorValue? {
        guard text.count <= 120 else { return nil }
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.hasSuffix(";") { s.removeLast() }
        if s.hasSuffix("!important") { s.removeLast("!important".count) }
        s = s.trimmingCharacters(in: .whitespaces)
        // An optional property name: "background-color: …", "--accent: …", "$primary: …".
        if let colon = s.firstIndex(of: ":"), !s[..<colon].contains("("),
           s[..<colon].allSatisfy({ $0.isLetter || $0.isNumber || "-_$@".contains($0) }) {
            s = s[s.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard !s.isEmpty, !s.contains("\n") else { return nil }

        if s.hasPrefix("#") { return hex(String(s.dropFirst())) }
        if s.hasPrefix("0x"), s.count == 8 { return hex(String(s.dropFirst(2))) }
        // Figma and most colour pickers copy hex without the #. Six hex digits on their own
        // count when they mix letters and digits, so a 2FA code like 123456 or a word like
        // "facade" doesn't get a swatch.
        if s.count == 6, s.allSatisfy(\.isHexDigit),
           (s.contains(where: \.isNumber) && s.contains(where: \.isLetter)) || s == "000000" || s == "ffffff" {
            return hex(s)
        }

        guard s.hasSuffix(")"), let open = s.firstIndex(of: "(") else { return nil }
        let name = String(s[..<open])
        let inner = s[s.index(after: open)..<s.index(before: s.endIndex)]
        guard let args = Args(String(inner)) else { return nil }
        switch name {
        case "rgb", "rgba": return rgb(args)
        case "hsl", "hsla": return hsl(args)
        case "hwb": return hwb(args)
        case "lab": return lab(args)
        case "lch": return lch(args)
        case "oklab": return oklab(args)
        case "oklch": return oklch(args)
        case "color": return color(args)
        default: return nil
        }
    }

    // MARK: - Formats

    private static func hex(_ h: String) -> ColorValue? {
        guard [3, 4, 6, 8].contains(h.count), h.allSatisfy(\.isHexDigit) else { return nil }
        let digits = h.count <= 4 ? h.flatMap { [$0, $0] } : Array(h)
        var values: [Double] = []
        for i in stride(from: 0, to: digits.count, by: 2) {
            guard let v = UInt8(String(digits[i...i + 1]), radix: 16) else { return nil }
            values.append(Double(v) / 255)
        }
        return ColorValue(red: values[0], green: values[1], blue: values[2], alpha: values.count == 4 ? values[3] : 1)
    }

    private static func rgb(_ a: Args) -> ColorValue? {
        guard a.count == 3,
              let r = a.number(0, percent: 255), let g = a.number(1, percent: 255), let b = a.number(2, percent: 255),
              let alpha = a.alpha else { return nil }
        return ColorValue(red: clamp(r / 255), green: clamp(g / 255), blue: clamp(b / 255), alpha: alpha)
    }

    private static func hsl(_ a: Args) -> ColorValue? {
        guard a.count == 3, let h = a.hue(0),
              let s = a.number(1, percent: 100), let l = a.number(2, percent: 100), let alpha = a.alpha else { return nil }
        let (r, g, b) = hslToRGB(h, clamp(s / 100), clamp(l / 100))
        return ColorValue(red: r, green: g, blue: b, alpha: alpha)
    }

    private static func hwb(_ a: Args) -> ColorValue? {
        guard a.count == 3, let h = a.hue(0),
              var w = a.number(1, percent: 100), var bl = a.number(2, percent: 100), let alpha = a.alpha else { return nil }
        w = clamp(w / 100); bl = clamp(bl / 100)
        if w + bl >= 1 {
            let grey = w / (w + bl)
            return ColorValue(red: grey, green: grey, blue: grey, alpha: alpha)
        }
        let (r, g, b) = hslToRGB(h, 1, 0.5)
        let f = { (c: Double) in c * (1 - w - bl) + w }
        return ColorValue(red: f(r), green: f(g), blue: f(b), alpha: alpha)
    }

    private static func lab(_ a: Args) -> ColorValue? {
        guard a.count == 3, let l = a.number(0, percent: 100),
              let x = a.number(1, percent: 125), let y = a.number(2, percent: 125), let alpha = a.alpha else { return nil }
        return labToSRGB(l, x, y, alpha)
    }

    private static func lch(_ a: Args) -> ColorValue? {
        guard a.count == 3, let l = a.number(0, percent: 100),
              let c = a.number(1, percent: 150), let h = a.hue(2), let alpha = a.alpha else { return nil }
        let rad = h * .pi / 180
        return labToSRGB(l, c * cos(rad), c * sin(rad), alpha)
    }

    private static func oklab(_ a: Args) -> ColorValue? {
        guard a.count == 3, let l = a.number(0, percent: 1),
              let x = a.number(1, percent: 0.4), let y = a.number(2, percent: 0.4), let alpha = a.alpha else { return nil }
        return oklabToSRGB(l, x, y, alpha)
    }

    private static func oklch(_ a: Args) -> ColorValue? {
        guard a.count == 3, let l = a.number(0, percent: 1),
              let c = a.number(1, percent: 0.4), let h = a.hue(2), let alpha = a.alpha else { return nil }
        let rad = h * .pi / 180
        return oklabToSRGB(l, c * cos(rad), c * sin(rad), alpha)
    }

    /// `color(srgb 0.2 0.5 1)` and `color(display-p3 …)`.
    private static func color(_ a: Args) -> ColorValue? {
        guard a.values.count >= 4, a.count == 4, let alpha = a.alpha else { return nil }
        let space = a.values[0]
        let inner = Args(values: Array(a.values.dropFirst()), alphaText: nil)
        guard let r = inner.number(0, percent: 1), let g = inner.number(1, percent: 1), let b = inner.number(2, percent: 1)
        else { return nil }
        switch space {
        case "srgb":
            return ColorValue(red: r, green: g, blue: b, alpha: alpha)
        case "display-p3":
            guard let c = NSColor(displayP3Red: r, green: g, blue: b, alpha: alpha).usingColorSpace(.extendedSRGB) else { return nil }
            return ColorValue(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent, alpha: alpha)
        default:
            return nil
        }
    }

    // MARK: - Maths

    private static func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }

    private static func hslToRGB(_ h: Double, _ s: Double, _ l: Double) -> (Double, Double, Double) {
        let f = { (n: Double) -> Double in
            let k = (n + h / 30).truncatingRemainder(dividingBy: 12)
            let a = s * min(l, 1 - l)
            return l - a * max(-1, min(k - 3, 9 - k, 1))
        }
        return (f(0), f(8), f(4))
    }

    /// Linear-light sRGB to the sRGB curve, keeping the sign for out-of-gamut values.
    private static func encode(_ c: Double) -> Double {
        let a = abs(c)
        let v = a <= 0.0031308 ? 12.92 * a : 1.055 * pow(a, 1 / 2.4) - 0.055
        return c < 0 ? -v : v
    }

    private static func oklabToSRGB(_ l: Double, _ a: Double, _ b: Double, _ alpha: Double) -> ColorValue {
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b
        let (L, M, S) = (l_ * l_ * l_, m_ * m_ * m_, s_ * s_ * s_)
        return ColorValue(red: encode(4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S),
                          green: encode(-1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S),
                          blue: encode(-0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S),
                          alpha: alpha)
    }

    /// CIE Lab (D50, as CSS uses it) to sRGB.
    private static func labToSRGB(_ l: Double, _ a: Double, _ b: Double, _ alpha: Double) -> ColorValue {
        let e = 216.0 / 24389, k = 24389.0 / 27
        let fy = (l + 16) / 116, fx = fy + a / 500, fz = fy - b / 200
        let xr = fx * fx * fx > e ? fx * fx * fx : (116 * fx - 16) / k
        let yr = l > k * e ? fy * fy * fy : l / k
        let zr = fz * fz * fz > e ? fz * fz * fz : (116 * fz - 16) / k
        let (x50, y50, z50) = (xr * 0.3457 / 0.3585, yr, zr * (1 - 0.3457 - 0.3585) / 0.3585)
        // Bradford D50 to D65, then XYZ to linear sRGB.
        let x = 0.955473421488075 * x50 - 0.02309845494876471 * y50 + 0.06325924320057072 * z50
        let y = -0.0283697093338637 * x50 + 1.0099953980813041 * y50 + 0.021041441191917323 * z50
        let z = 0.012314014864481998 * x50 - 0.020507649298898964 * y50 + 1.330365926242124 * z50
        return ColorValue(red: encode(3.2409699419045226 * x - 1.537383177570094 * y - 0.4986107602930034 * z),
                          green: encode(-0.9692436362808796 * x + 1.8759675015077202 * y + 0.04155505740717559 * z),
                          blue: encode(0.05563007969699366 * x - 0.20397695888897652 * y + 1.0569715142428786 * z),
                          alpha: alpha)
    }
}

/// The arguments inside a CSS colour function, in either syntax: `255, 0, 0, 0.5` or `255 0 0 / 50%`.
private struct Args {
    let values: [String]
    let alphaText: String?

    init(values: [String], alphaText: String?) {
        self.values = values
        self.alphaText = alphaText
    }

    init?(_ s: String) {
        let slash = s.split(separator: "/", omittingEmptySubsequences: false)
        guard slash.count <= 2 else { return nil }
        let main = slash[0].split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\t" }).map(String.init)
        if slash.count == 2 {
            let a = slash[1].trimmingCharacters(in: .whitespaces)
            guard !a.isEmpty, !a.contains(" "), !s.contains(",") else { return nil }
            values = main
            alphaText = a
        } else if main.count == 4, s.contains(",") || main.first == "srgb" || main.first == "display-p3" {
            // The legacy rgba(r, g, b, a); color() has its space name first instead.
            values = main.first?.first?.isLetter == true ? main : Array(main.prefix(3))
            alphaText = main.first?.first?.isLetter == true ? nil : main[3]
        } else {
            values = main
            alphaText = nil
        }
    }

    /// How many components there are, not counting the alpha.
    var count: Int { values.count }

    /// 1 when no alpha was given, nil when it isn't a number.
    var alpha: Double? {
        guard let alphaText else { return 1 }
        guard let v = Self.value(alphaText, percent: 1) else { return nil }
        return min(max(v, 0), 1)
    }

    /// The component as a number; a percentage is scaled so 100% gives `percent`.
    func number(_ i: Int, percent: Double) -> Double? {
        i < values.count ? Self.value(values[i], percent: percent) : nil
    }

    /// The hue in degrees: a bare number, or deg, rad, grad or turn.
    func hue(_ i: Int) -> Double? {
        guard i < values.count else { return nil }
        let v = values[i]
        let units: [(String, Double)] = [("deg", 1), ("grad", 0.9), ("rad", 180 / .pi), ("turn", 360)]
        var degrees: Double?
        if v == "none" { degrees = 0 }
        for (unit, scale) in units where v.hasSuffix(unit) {
            degrees = Double(v.dropLast(unit.count)).map { $0 * scale }
            break
        }
        if degrees == nil, v.last?.isLetter != true { degrees = Double(v) }
        guard let d = degrees, d.isFinite else { return nil }
        let r = d.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }

    private static func value(_ v: String, percent: Double) -> Double? {
        if v == "none" { return 0 }
        if v.hasSuffix("%") { return Double(v.dropLast()).map { $0 / 100 * percent } }
        guard let d = Double(v), d.isFinite else { return nil }
        return d
    }
}
