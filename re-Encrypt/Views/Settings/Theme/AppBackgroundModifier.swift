import SwiftUI
import AppKit

// MARK: - App Background Extension

extension View {
    func appBackground() -> some View {
        self.modifier(AppBackgroundModifier())
    }
    /// Apply adaptive foreground color based on theme
    func adaptiveTextColor(_ theme: ThemeManager, priority: TextPriority = .primary) -> some View {
        self.foregroundColor(theme.textColor(for: priority))
    }
    
    /// Apply theme-aware card background
    func cardBackground(_ theme: ThemeManager) -> some View {
        self
            .background(theme.adaptiveTileBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(theme.isDarkBackground ? Color.white.opacity(0.1) : Color.clear, lineWidth: 1)
            )
    }
    
    /// Apply theme-aware selection style
    func selectionStyle(_ theme: ThemeManager, isSelected: Bool) -> some View {
        self
            .background(isSelected ? theme.adaptiveSelectionFill : Color.clear)
            .cornerRadius(8)
    }
}

// MARK: - App Background Modifier

struct AppBackgroundModifier: ViewModifier {
    @EnvironmentObject private var theme: ThemeManager
    @AppStorage("Settings.blurMaterial") private var blurMaterialRaw: String = "hudWindow"
    @AppStorage("Settings.transparency") private var transparency: Double = 0.8
    @AppStorage("Settings.useTint") private var useTint: Bool = false
    @AppStorage("Settings.transparencyEnabled") private var transparencyEnabled: Bool = false
    
    func body(content: Content) -> some View {
        if transparencyEnabled {
            // Apply glass/transparency effect
            content
                .foregroundStyle(theme.primaryTextColor)
                .tint(theme.badgeBackground)
                .background(
                    ZStack {
                        VisualEffectBlur(
                            material: material(from: blurMaterialRaw),
                            blendingMode: .behindWindow,
                            alphaValue: transparency
                        )
                        
                        if useTint {
                            theme.backgroundColor.opacity(0.3)
                        }
                    }
                )
        } else {
            // Solid color background (no transparency)
            content
                .foregroundStyle(theme.primaryTextColor)
                .tint(theme.badgeBackground)
                .background(theme.backgroundColor)
        }
    }
    
    private func material(from name: String) -> NSVisualEffectView.Material {
        switch name {
        case "popover": return .popover
        case "sidebar": return .sidebar
        case "menu": return .menu
        case "underWindow": return .underWindowBackground
        default: return .hudWindow
        }
    }
}

// MARK: - Visual Effect Blur

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var alphaValue: Double = 1.0
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.alphaValue = alphaValue
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.alphaValue = alphaValue
    }
}

// MARK: - Adaptive Color Helpers
enum TextPriority {
    case primary
    case secondary
    case tertiary
}

// MARK: - Visual Effect View (macOS)

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let effectView = NSVisualEffectView()
        effectView.material = material
        effectView.blendingMode = blendingMode
        effectView.state = .active
        return effectView
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Adaptive Styles

struct AdaptiveButtonStyle: ButtonStyle {
    @EnvironmentObject private var theme: ThemeManager
    var isProminent: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isProminent ? theme.badgeBackground : theme.adaptiveTileBackground)
            )
            .foregroundColor(isProminent ? .white : theme.primaryTextColor)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct AdaptiveToggleStyle: ToggleStyle {
    @EnvironmentObject private var theme: ThemeManager
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
                .foregroundColor(theme.primaryTextColor)
            
            Spacer()
            
            Toggle("", isOn: configuration.$isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(theme.badgeBackground)
        }
    }
}

// MARK: - Adaptive Input Field

struct AdaptiveTextField: View {
    let placeholder: String
    @Binding var text: String
    @EnvironmentObject private var theme: ThemeManager
    @FocusState private var isFocused: Bool
    
    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .padding(10)
            .background(theme.isDarkBackground ? Color.white.opacity(0.08) : Color.primary.opacity(0.06))
            .foregroundColor(theme.primaryTextColor)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isFocused ? theme.badgeBackground : Color.clear, lineWidth: 2)
            )
            .focused($isFocused)
    }
}
