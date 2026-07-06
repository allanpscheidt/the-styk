import AppKit

enum Theme {

    static func nsColor(_ c: NoteColor) -> NSColor {
        switch c {
        case .yellow: return rgb(0xFFE066)
        case .pink:   return rgb(0xFFB3C7)
        case .blue:   return rgb(0x9AD1FF)
        case .green:  return rgb(0xB5E8A0)
        case .orange: return rgb(0xFFC97A)
        case .purple: return rgb(0xD9BBFF)
        }
    }

    static func font(_ s: NoteStyle) -> NSFont {
        let size = CGFloat(min(max(s.fontSize, 8), 72))
        switch s.fontID {
        case .system:
            return .systemFont(ofSize: size)
        case .rounded:
            if #available(macOS 10.15, *) { return designed(.rounded, size: size) }
            return .systemFont(ofSize: size)          // ≤10.14: sem SF Rounded
        case .serif:
            if #available(macOS 10.15, *) { return designed(.serif, size: size) }
            return NSFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size)
        case .mono:
            if #available(macOS 10.15, *) { return designed(.monospaced, size: size) }
            return NSFont(name: "Menlo", size: size) ?? .systemFont(ofSize: size)
        case .hand:
            return NSFont(name: "Noteworthy", size: size)
                ?? NSFont(name: "Marker Felt", size: size)
                ?? .systemFont(ofSize: size)
        }
    }

    static func label(_ c: NoteColor) -> String {
        switch c {
        case .yellow: return L("Amarelo")
        case .pink:   return L("Rosa")
        case .blue:   return L("Azul")
        case .green:  return L("Verde")
        case .orange: return L("Laranja")
        case .purple: return L("Roxo")
        }
    }

    @available(macOS 10.15, *)
    private static func designed(_ design: NSFontDescriptor.SystemDesign, size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size)
        guard let descriptor = base.fontDescriptor.withDesign(design),
              let font = NSFont(descriptor: descriptor, size: size) else { return base }
        return font
    }

    private static func rgb(_ v: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255,
                alpha: 1)
    }
}
