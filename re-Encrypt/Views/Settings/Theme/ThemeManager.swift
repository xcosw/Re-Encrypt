import SwiftUI
import AppKit
internal import Combine

// MARK: - Theme Presets

struct ThemePreset {
    let name: String
    let selectionFill: Color
    let tileBackground: Color
    let badgeBackground: Color
    let backgroundColor: Color
    let usesSystemAppearance: Bool
    
    static let presets: [ThemePreset] = [
        // Default dark theme
        ThemePreset(
            name: "Default Dark",
            selectionFill: Color.red.opacity(0.25),
            tileBackground: Color.white.opacity(0.08),
            badgeBackground: Color.red,
            backgroundColor: Color.black,
            usesSystemAppearance: false
        ),
        
        // Light Themes
        ThemePreset(
            name: "Glance",
            selectionFill: Color(red: 0.0, green: 0.48, blue: 1.0).opacity(0.15),
            tileBackground: Color(red: 0.96, green: 0.97, blue: 0.98, opacity: 0.9),
            badgeBackground: Color(red: 0.0, green: 0.48, blue: 1.0),
            backgroundColor: Color(hex: "#F8F9FAFF") ?? .white,
            usesSystemAppearance: true
        ),
        
        ThemePreset(
            name: "Mint",
            selectionFill: Color(red: 0.2, green: 0.75, blue: 0.55).opacity(0.15),
            tileBackground: Color(red: 0.94, green: 0.99, blue: 0.97, opacity: 0.85),
            badgeBackground: Color(red: 0.15, green: 0.75, blue: 0.55),
            backgroundColor: Color(hex: "#F0FBF7FF") ?? .white,
            usesSystemAppearance: false
        ),
        
        ThemePreset(
            name: "Lavender",
            selectionFill: Color(red: 0.65, green: 0.45, blue: 0.95).opacity(0.15),
            tileBackground: Color(red: 0.97, green: 0.95, blue: 1.0, opacity: 0.85),
            badgeBackground: Color(red: 0.6, green: 0.4, blue: 0.95),
            backgroundColor: Color(hex: "#F7F5FFFF") ?? .white,
            usesSystemAppearance: false
        ),
        
        // Dark Themes
        ThemePreset(
            name: "Slate",
            selectionFill: Color(red: 0.35, green: 0.55, blue: 0.95).opacity(0.25),
            tileBackground: Color(red: 0.15, green: 0.17, blue: 0.2, opacity: 0.7),
            badgeBackground: Color(red: 0.35, green: 0.55, blue: 0.95),
            backgroundColor: Color(hex: "#1E222AFF") ?? .black,
            usesSystemAppearance: false
        ),
        
        ThemePreset(
            name: "Obsidian",
            selectionFill: Color.white.opacity(0.15),
            tileBackground: Color.white.opacity(0.06),
            badgeBackground: Color(red: 0.7, green: 0.7, blue: 0.7),
            backgroundColor: Color(hex: "#0F0F0FFF") ?? .black,
            usesSystemAppearance: false
        ),
        
        ThemePreset(
            name: "Midnight Blue",
            selectionFill: Color(red: 0.3, green: 0.6, blue: 1.0).opacity(0.25),
            tileBackground: Color(red: 0.12, green: 0.17, blue: 0.28, opacity: 0.7),
            badgeBackground: Color(red: 0.3, green: 0.6, blue: 1.0),
            backgroundColor: Color(hex: "#0A0E1AFF") ?? .black,
            usesSystemAppearance: false
        ),
        
        ThemePreset(
            name: "Forest Night",
            selectionFill: Color(red: 0.3, green: 0.85, blue: 0.55).opacity(0.22),
            tileBackground: Color(red: 0.1, green: 0.2, blue: 0.16, opacity: 0.7),
            badgeBackground: Color(red: 0.25, green: 0.85, blue: 0.55),
            backgroundColor: Color(hex: "#0A1410FF") ?? .black,
            usesSystemAppearance: false
        ),
    ]
    
    static func preset(named: String) -> ThemePreset? {
        presets.first { $0.name == named }
    }
}

// MARK: - Theme Manager

final class ThemeManager: ObservableObject {
    // Persisted theme name
    @AppStorage("Theme.name") var themeName: String = "Default Dark" {
        didSet {
            if oldValue != themeName {
                applyPreset(themeName)
            }
        }
    }
    
    // Follow system appearance
    @AppStorage("Theme.followSystem") var followSystemAppearance: Bool = false {
        didSet { objectWillChange.send() }
    }

    // Persisted colors as hex strings (RGBA)
    @AppStorage("Theme.selection") private var selectionHex: String = ""
    @AppStorage("Theme.tile") private var tileHex: String = ""
    @AppStorage("Theme.badge") private var badgeHex: String = ""
    @AppStorage("Theme.background") private var backgroundHex: String = ""

    // MARK: - Computed Color Properties
    
    var selectionFill: Color {
        get {
            if followSystemAppearance {
                return Color(NSColor.controlAccentColor).opacity(0.15)
            }
            return color(from: selectionHex) ?? Color.red.opacity(0.25)
        }
        set {
            selectionHex = hex(from: newValue)
            objectWillChange.send()
        }
    }

    var tileBackground: Color {
        get {
            if followSystemAppearance {
                return Color(NSColor.windowBackgroundColor).opacity(0.6)
            }
            return color(from: tileHex) ?? Color.white.opacity(0.08)
        }
        set {
            tileHex = hex(from: newValue)
            objectWillChange.send()
        }
    }

    var badgeBackground: Color {
        get {
            if followSystemAppearance {
                return Color(NSColor.controlAccentColor)
            }
            return color(from: badgeHex) ?? Color.red
        }
        set {
            badgeHex = hex(from: newValue)
            objectWillChange.send()
        }
    }
    
    var backgroundColor: Color {
        get {
            if followSystemAppearance {
                return Color(NSColor.windowBackgroundColor)
            }
            return color(from: backgroundHex) ?? Color.black
        }
        set {
            backgroundHex = hex(from: newValue)
            objectWillChange.send()
        }
    }
    
    // MARK: - Adaptive Properties
    
    var primaryTextColor: Color {
        isDarkBackground ? Color.white : Color.black
    }
    
    var secondaryTextColor: Color {
        isDarkBackground ? Color.white.opacity(0.7) : Color.black.opacity(0.7)
    }
    
    var tertiaryTextColor: Color {
        isDarkBackground ? Color.white.opacity(0.5) : Color.black.opacity(0.5)
    }
    
    var iconColor: Color {
        isDarkBackground ? Color.white.opacity(0.9) : Color.black.opacity(0.85)
    }
    
    var adaptiveTileBackground: Color {
        isDarkBackground ? Color.white.opacity(0.08) : tileBackground
    }
    
    var adaptiveSelectionFill: Color {
        isDarkBackground ? badgeBackground.opacity(0.25) : selectionFill
    }
    
    var isDarkBackground: Bool {
        let bgColor = NSColor(backgroundColor)
        guard let rgb = bgColor.usingColorSpace(.sRGB) else { return false }
        
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance < 0.4
    }
    
    // MARK: - Public Methods
    
    func applyPreset(_ name: String) {
        guard let preset = ThemePreset.preset(named: name) else { return }
        
        followSystemAppearance = preset.usesSystemAppearance
        
        if !preset.usesSystemAppearance {
            selectionFill = preset.selectionFill
            tileBackground = preset.tileBackground
            badgeBackground = preset.badgeBackground
            backgroundColor = preset.backgroundColor
        }
        
        objectWillChange.send()
    }

    func resetToSystem() {
        themeName = "System"
        followSystemAppearance = true
        selectionHex = ""
        tileHex = ""
        badgeHex = ""
        backgroundHex = ""
        objectWillChange.send()
    }
    
    func textColor(for priority: TextPriority) -> Color {
        switch priority {
        case .primary: return primaryTextColor
        case .secondary: return secondaryTextColor
        case .tertiary: return tertiaryTextColor
        }
    }
    
    // MARK: - Private Helpers
    
    private func hex(from color: Color) -> String {
        let base = NSColor(color)
        let rgb = base.usingColorSpace(.sRGB)
            ?? base.usingColorSpace(.deviceRGB)
            ?? base.usingColorSpace(.genericRGB)
            ?? base

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getRed(&r, green: &g, blue: &b, alpha: &a)

        let ri = UInt8(clamping: Int(r * 255))
        let gi = UInt8(clamping: Int(g * 255))
        let bi = UInt8(clamping: Int(b * 255))
        let ai = UInt8(clamping: Int(a * 255))
        return String(format: "#%02X%02X%02X%02X", ri, gi, bi, ai)
    }

    private func color(from hex: String) -> Color? {
        guard hex.hasPrefix("#"), hex.count == 9 else { return nil }
        let hexString = String(hex.dropFirst())
        guard let value = UInt32(hexString, radix: 16) else { return nil }
        let r = Double((value >> 24) & 0xFF) / 255.0
        let g = Double((value >> 16) & 0xFF) / 255.0
        let b = Double((value >> 8) & 0xFF) / 255.0
        let a = Double(value & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        guard hex.hasPrefix("#"), hex.count == 9 else { return nil }
        let hexString = String(hex.dropFirst())
        guard let value = UInt32(hexString, radix: 16) else { return nil }
        let r = Double((value >> 24) & 0xFF) / 255.0
        let g = Double((value >> 16) & 0xFF) / 255.0
        let b = Double((value >> 8) & 0xFF) / 255.0
        let a = Double(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, opacity: a)
    }
}
