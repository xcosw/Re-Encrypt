import SwiftUI
import AppKit

// MARK: - Notification Extensions

extension Notification.Name {
    
    // MARK: - App Lifecycle
    static let appResetRequired = Notification.Name("appResetRequired")
    static let applicationLocked = Notification.Name("applicationLocked")
    // MARK: - Security Events
    static let memoryPressureDetected = Notification.Name("memoryPressureDetected")
    static let sessionExpired = Notification.Name("sessionExpired")
    
    // MARK: - Unified Idle System
    static let autoLockSettingsChanged = Notification.Name("autoLockSettingsChanged")
    // 🌟 Triggers from unified controller
    static let autoLockTriggered = Notification.Name("autoLockTriggered")
    static let autoCloseTriggered = Notification.Name("autoCloseTriggered")
    
    static let twoFactorRequired = Notification.Name("twoFactorRequired")
    static let userActivityDetected = Notification.Name("userActivityDetected")
    static let securityThreatDetected = Notification.Name("SecurityThreatDetected")
    static let memoryPressureSettingsChanged = Notification.Name("memoryPressureSettingsChanged")
    // MARK: - Screenshot Detection
    static let screenshotSettingsChanged = Notification.Name("screenshotSettingsChanged")
    static let screenshotDetected = Notification.Name("screenshotDetected")
    static let emergencyShutdown = Notification.Name("EmergencyShutdown")
    
    //static let deviceBindingChanged = Notification.Name("deviceBindingChanged")
}

// MARK: - Settings Category

enum SettingsCategory: String, CaseIterable, Identifiable {
    case security = "Security"
    case theme = "Appearance"
    case autoLock = "Auto-Lock"
    case session = "Session"
    case clipboard = "Clipboard"
    case monitoring = "Monitoring"
    case backup = "Backup"
    case danger = "Advanced"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .security: return "lock.shield.fill"
        case .theme: return "paintpalette.fill"
        case .autoLock: return "lock.rotation"
        case .session: return "clock.arrow.circlepath"
        case .clipboard: return "doc.on.doc.fill"
        case .monitoring: return "eye.fill"
        case .backup: return "arrow.up.doc.fill"
        case .danger: return "exclamationmark.triangle.fill"
        }
    }
    
    var iconColor: Color {
        switch self {
        case .security: return .green
        case .theme: return .purple
        case .autoLock: return .orange
        case .session: return .blue
        case .clipboard: return .indigo
        case .monitoring: return .cyan
        case .backup: return .teal
        case .danger: return .red
        }
    }
}

// MARK: - Security Configuration Manager
@available(macOS 15.0, *)
@MainActor
class SecurityConfigManager: ObservableObject {
    static let shared = SecurityConfigManager()
    
    @Published var sessionTimeout: TimeInterval {
        didSet {
            Task { await CryptoHelper.setSessionTimeout(sessionTimeout) }
        }
    }
    
    @Published var autoLockOnBackground: Bool {
        didSet {
            Task {
                print("🔧 [SecurityConfig] autoLockOnBackground changed to: \(autoLockOnBackground)")
                await CryptoHelper.setAutoLockOnBackground(autoLockOnBackground)
                
                let verified = await CryptoHelper.getAutoLockOnBackground()
                print("✅ [SecurityConfig] Verified saved value: \(verified)")
            }
        }
    }
    
    private init() {
        // Provide default values; async values will be loaded in `reload()`
        self.sessionTimeout = 0
        self.autoLockOnBackground = false
        
        Task {
            await self.reload()
        }
    }
    
    func reload() async {
        self.sessionTimeout = await CryptoHelper.getSessionTimeout()
        self.autoLockOnBackground = await CryptoHelper.getAutoLockOnBackground()
    }
}


// MARK: - Settings View

@available(macOS 15.0, *)
struct SettingsView: View {
    // Environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject var memoryMonitor: MemoryPressureMonitor
    @EnvironmentObject private var screenshotDetector: ScreenshotDetectionManager
    
    // App Storage
   // @AppStorage("AutoLockEnabled") private var autoLockEnabled: Bool = false
    @AppStorage("Settings.blurMaterial") private var blurMaterialRaw: String = "hudWindow"
    @AppStorage("Settings.transparency") private var transparency: Double = 0.8
    @AppStorage("Settings.transparencyEnabled") private var transparencyEnabled: Bool = false
    @AppStorage("Settings.useTint") private var useTint: Bool = false
        
    @State private var autoLockInterval: Double = 60
    @State private var autoClearClipboard: Bool = true
    @State private var clearDelay: Int = 10
    @State private var autoCloseEnabled: Bool = false
    @State private var autoCloseInterval: Double = 10
    
    // State
    @State private var selectedCategory: SettingsCategory = .security
    @State private var showConfirm = false
    @State private var showPasswordPrompt = false
    @State private var showError = false
    @State private var showSuccess = false
    @State private var enteredPasswordData: SecData? = nil
    @State private var showDeleteConfirm = false
    @State private var showingSessionDetails = false
    @StateObject private var configManager = SecurityConfigManager.shared
    @State private var autoLockEnabled: Bool = false 


    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            sidebar
            
            Divider()
            
            // Content
            VStack(spacing: 0) {
                header
                Divider()
                
                ScrollView {
                    contentForCategory(selectedCategory)
                        .padding()
                }
            }
            .frame(minWidth: 500)
        }
        .frame(minWidth: 800, minHeight: 600)
        .sheet(isPresented: $showPasswordPrompt) { passwordPrompt }
        .sheet(isPresented: $showingSessionDetails) { SessionDetailsView() }
        .alert("Invalid Password", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The master password entered is incorrect. Please try again.")
        }
        .alert("Delete All Data?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Task {
                    await wipeAllAppData()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all app data including saved passwords and settings. This action cannot be undone.")
        }
        .alert("Success", isPresented: $showSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Storage backend successfully changed.")
        }
        .appBackground()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { Task{
                await loadSecureSettings()}
            }
        }
    }

    // MARK: - Sidebar
    
    private var sidebar: some View {
        VStack(spacing: 0) {
            // Sidebar Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.title2.weight(.bold))
                    .foregroundColor(theme.primaryTextColor)
                
                Text("Configure your app")
                    .font(.caption)
                    .foregroundColor(theme.secondaryTextColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            
            Divider()
            
            // Categories
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(SettingsCategory.allCases) { category in
                        SidebarButton(
                            category: category,
                            isSelected: selectedCategory == category
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedCategory = category
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            
            Spacer()
            
            // Footer
            VStack(spacing: 12) {
                SecurityStatusPopoverButton()
                    .environmentObject(memoryMonitor)
                
                Button {
                    dismiss()
                } label: {
                    Label("Close Settings", systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding()
        }
        .frame(width: 220)
        .background(theme.isDarkBackground ? Color.black.opacity(0.2) : Color.gray.opacity(0.05))
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(selectedCategory.iconColor.opacity(0.15))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: selectedCategory.icon)
                            .font(.system(size: 20))
                            .foregroundColor(selectedCategory.iconColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedCategory.rawValue)
                            .font(.title3.weight(.semibold))
                            .foregroundColor(theme.primaryTextColor)
                        
                        Text(subtitleForCategory(selectedCategory))
                            .font(.caption)
                            .foregroundColor(theme.secondaryTextColor)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Content Sections
    
    @ViewBuilder
    private func contentForCategory(_ category: SettingsCategory) -> some View {
        switch category {
        case .security:
            securityContent
        case .theme:
            themeContent
        case .autoLock:
            autoLockContent
        case .session:
            sessionContent
        case .clipboard:
            clipboardContent
        case .monitoring:
            monitoringContent
        case .backup:
            backupContent
        case .danger:
            dangerContent
        }
    }
    
    private func subtitleForCategory(_ category: SettingsCategory) -> String {
        switch category {
        case .security: return "Authentication and storage settings"
        case .theme: return "Customize the look and feel"
        case .autoLock: return "Configure automatic locking"
        case .session: return "Manage encryption sessions"
        case .clipboard: return "Clipboard security settings"
        case .monitoring: return "Monitoring security settings"
        case .backup: return "Export and import your data"
        case .danger: return "Destructive actions and data management"
        }
    }
    
    // MARK: - Security Content
    
    private var securityContent: some View {
        VStack(spacing: 20) {
            // Two-Factor Authentication
            SettingsCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Two-Factor Authentication")
                        .font(.headline)
                        .foregroundColor(theme.primaryTextColor)
                    
                    Divider()
                    
                    TwoFactorSettingsView()
                }
            }
            
            // Biometric Authentication
            SettingsCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Biometric Authentication")
                        .font(.headline)
                        .foregroundColor(theme.primaryTextColor)
                    
                    Divider()
                    
                    if BiometricManager.shared.isBiometricAvailable {
                        SettingsToggleRow(
                            icon: BiometricManager.shared.biometricSystemImage(),
                            iconColor: .green,
                            title: "Enable \(BiometricManager.shared.biometricDisplayName())",
                            subtitle: "Use \(BiometricManager.shared.biometricDisplayName()) for quick unlock. You'll still need your master password for sensitive operations.",
                            isOn: Binding(
                                get: { CryptoHelper.biometricUnlockEnabled },
                                set: { newValue in
                                    if newValue {
                                        CryptoHelper.enableBiometricUnlock()
                                    } else {
                                        CryptoHelper.disableBiometricUnlock()
                                    }
                                }
                            )
                        )
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.title3)
                            Text("Biometric authentication not available on this device")
                                .font(.subheadline)
                                .foregroundColor(theme.secondaryTextColor)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
            
           /* SettingsCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Device Binding")
                        .font(.headline)
                        .foregroundColor(theme.primaryTextColor)
                    
                    Divider()
                    
                    DeviceBindingSettingsView()
                        .environmentObject(theme)
                        .environment(\.managedObjectContext, viewContext)
                }
            }*/
        }
    }
    
    // MARK: - Theme Content
    
    private var themeContent: some View {
        VStack(spacing: 20) {
            // Theme Presets
            SettingsCard {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Theme Presets")
                        .font(.headline)
                        .foregroundColor(theme.primaryTextColor)
                    
                    Divider()
                    
                    Picker("Theme Preset", selection: $theme.themeName) {
                        ForEach(ThemePreset.presets.indices, id: \.self) { index in
                            let preset = ThemePreset.presets[index]
                            HStack {
                                if preset.usesSystemAppearance {
                                    Image(systemName: "gear.circle.fill")
                                }
                                Text(preset.name)
                            }
                            .tag(preset.name)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Divider()
                    
                    SettingsToggleRow(
                        icon: "sun.max.fill",
                        iconColor: .orange,
                        title: "Follow System Appearance",
                        subtitle: "Automatically adapt to system light/dark mode",
                        isOn: $theme.followSystemAppearance
                    )
                    
                    if !theme.followSystemAppearance && theme.themeName != "System" {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Customize Colors")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(theme.primaryTextColor)
                            
                            swatchPickerRow(title: "Background Color", selection: Binding(get: { theme.backgroundColor }, set: { theme.backgroundColor = $0 }), palette: backgroundPalette)
                            swatchPickerRow(title: "Selection Highlight", selection: Binding(get: { theme.selectionFill }, set: { theme.selectionFill = $0 }), palette: selectionPalette)
                            swatchPickerRow(title: "Tile Background", selection: Binding(get: { theme.tileBackground }, set: { theme.tileBackground = $0 }), palette: tilePalette)
                            swatchPickerRow(title: "Badge Background", selection: Binding(get: { theme.badgeBackground }, set: { theme.badgeBackground = $0 }), palette: badgePalette)
                        }
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Preview")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(theme.primaryTextColor)
                        
                        HStack(spacing: 12) {
                            PreviewBox(color: theme.selectionFill, label: "Select")
                            PreviewBox(color: theme.tileBackground, label: "Tile")
                            PreviewBox(color: theme.badgeBackground, label: "Badge", textColor: .white)
                        }
                    }
                    
                    HStack {
                        Spacer()
                        Button("Reset to System") {
                            theme.resetToSystem()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            
            // Transparency & Blur
            SettingsCard {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Transparency & Blur")
                        .font(.headline)
                        .foregroundColor(theme.primaryTextColor)
                    
                    Text("Adjust window appearance effects")
                        .font(.subheadline)
                        .foregroundColor(theme.secondaryTextColor)
                    
                    Divider()
                    
                    SettingsToggleRow(
                        icon: "sparkles",
                        iconColor: .cyan,
                        title: "Enable Transparency",
                        subtitle: "Apply glass effect with blur and transparency",
                        isOn: $transparencyEnabled
                    )
                    
                    if transparencyEnabled {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Glass Transparency")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(theme.primaryTextColor)
                                Spacer()
                                Text("\(Int(transparency * 100))%")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundColor(theme.secondaryTextColor)
                            }
                            
                            Slider(value: $transparency, in: 0.0...1.0, step: 0.05)
                            
                            HStack(spacing: 8) {
                                ForEach([("0%", 0.0), ("50%", 0.5), ("80%", 0.8), ("100%", 1.0)], id: \.0) { label, value in
                                    Button(label) {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            transparency = value
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .tint(abs(transparency - value) < 0.05 ? theme.badgeBackground : .gray)
                                }
                            }
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Blur Style")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(theme.primaryTextColor)
                            
                            Picker("Blur Style", selection: $blurMaterialRaw) {
                                Text("HUD").tag("hudWindow")
                                Text("Popover").tag("popover")
                                Text("Sidebar").tag("sidebar")
                                Text("Menu").tag("menu")
                                Text("Under").tag("underWindow")
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        Divider()
                        
                        SettingsToggleRow(
                            icon: "paintbrush.fill",
                            iconColor: .purple,
                            title: "Enable Color Tint",
                            subtitle: "Add a subtle color overlay on top of the glass effect",
                            isOn: $useTint
                        )
                        
                        if useTint {
                            swatchPickerRow(title: "Tint Color", selection: Binding(get: { theme.backgroundColor }, set: { theme.backgroundColor = $0 }), palette: backgroundPalette)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Auto-Lock Content
    
    private var autoLockContent: some View {
        VStack(spacing: 20) {
            // Inactivity Lock
            SettingsCard {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Inactivity Lock")
                        .font(.headline)
                        .foregroundColor(theme.primaryTextColor)
                    
                    Text("Lock the app after a period of inactivity")
                        .font(.subheadline)
                        .foregroundColor(theme.secondaryTextColor)
                    
                    Divider()
                    
                    SettingsToggleRow(
                        icon: "lock.badge.clock.fill",
                        iconColor: .blue,
                        title: "Lock after inactivity",
                        subtitle: nil,
                        isOn: $autoLockEnabled
                    )
                    .onChange(of: autoLockEnabled) { _, newValue in
                        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        print("[Settings] Auto-lock enabled: \(newValue)")
                        Task {
                            await CryptoHelper.setAutoLockEnabled(newValue)
                        }
                        // 🌟 Notify unified controller to restart
                        NotificationCenter.default.post(
                            name: .autoLockSettingsChanged,
                            object: nil
                        )
                        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    }
                    
                    if autoLockEnabled {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Lock after:")
                                    .font(.subheadline)
                                    .foregroundColor(theme.secondaryTextColor)
                                Spacer()
                                Text("\(Int(autoLockInterval))s")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundColor(theme.primaryTextColor)
                            }
                            
                            Slider(value: $autoLockInterval, in: 30...3600, step: 30)
                                .onChange(of: autoLockInterval) { _, newValue in
                                    print("[Settings] Auto-lock interval: \(Int(newValue))s")
                                    Task{
                                        await CryptoHelper.setAutoLockInterval(Int(newValue))
                                }
                                    // 🌟 Notify unified controller
                                    NotificationCenter.default.post(
                                        name: .autoLockSettingsChanged,
                                        object: nil
                                    )
                                }
                            
                            Text("App will lock after \(Int(autoLockInterval)) seconds of no keyboard/mouse activity")
                                .font(.caption)
                                .foregroundColor(theme.secondaryTextColor)
                            
                            HStack(spacing: 8) {
                                Text("Quick presets:")
                                    .font(.caption)
                                    .foregroundColor(theme.secondaryTextColor)
                                Button("30s") { autoLockInterval = 30 }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                Button("1m") { autoLockInterval = 60 }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                Button("5m") { autoLockInterval = 300 }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                Button("15m") { autoLockInterval = 900 }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                            }
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
            }
            
            // Background Lock
            SettingsCard {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Background Lock")
                        .font(.headline)
                        .foregroundColor(theme.primaryTextColor)
                    
                    Divider()
                    
                    SettingsToggleRow(
                        icon: "app.badge",
                        iconColor: .orange,
                        title: "Lock when app goes to background",
                        subtitle: "Immediately locks when you switch to another app or hide the window",
                        isOn: $configManager.autoLockOnBackground
                    )
                }
            }
            
            // Auto-Close
            SettingsCard {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Auto-Close App")
                        .font(.headline)
                        .foregroundColor(theme.primaryTextColor)
                    
                    Text("Automatically quit app after extended inactivity")
                        .font(.subheadline)
                        .foregroundColor(theme.secondaryTextColor)
                    
                    Divider()
                    
                    SettingsToggleRow(
                        icon: "power",
                        iconColor: .red,
                        title: "Enable Auto-Close",
                        subtitle: nil,
                        isOn: $autoCloseEnabled
                    )
                    .onChange(of: autoCloseEnabled) { _, newValue in
                        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        print("[Settings] Auto-close enabled: \(newValue)")
                        Task{
                            await CryptoHelper.setAutoCloseEnabled(newValue)
                        }
                        // 🌟 Notify unified controller to restart
                        NotificationCenter.default.post(
                            name: .autoLockSettingsChanged,
                            object: nil
                        )
                        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    }
                    
                    if autoCloseEnabled {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Close after")
                                    .font(.subheadline)
                                    .foregroundColor(theme.secondaryTextColor)
                                Spacer()
                                Text("\(Int(autoCloseInterval)) min")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundColor(theme.primaryTextColor)
                            }
                            
                            Slider(value: $autoCloseInterval, in: 1...120, step: 1)
                                .onChange(of: autoCloseInterval) { _, newValue in
                                    print("[Settings] Auto-close interval: \(Int(newValue)) min")
                                    Task{
                                        await CryptoHelper.setAutoCloseInterval(Int(newValue)) }
                                    
                                    // 🌟 Notify unified controller
                                    NotificationCenter.default.post(
                                        name: .autoLockSettingsChanged,
                                        object: nil
                                    )
                                }
                            
                            Text("If there is no user activity for this period, the app will automatically close (quit) for your security.")
                                .font(.caption)
                                .foregroundColor(theme.secondaryTextColor)
                            
                            // 🌟 Warning for short intervals
                            if autoCloseInterval < 5 {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("Very short interval - app will close quickly!")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                                .padding(8)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(6)
                            }
                            
                            HStack(spacing: 8) {
                                Text("Quick presets:")
                                    .font(.caption)
                                    .foregroundColor(theme.secondaryTextColor)
                                Button("5m") { autoCloseInterval = 5 }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                Button("10m") { autoCloseInterval = 10 }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                Button("30m") { autoCloseInterval = 30 }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                Button("1h") { autoCloseInterval = 60 }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                            }
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
            }
            
            // 🌟 Combined Status Display
            if autoLockEnabled || autoCloseEnabled {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text("Active Timers")
                                .font(.headline)
                                .foregroundColor(theme.primaryTextColor)
                        }
                        
                        Divider()
                        
                        if autoLockEnabled {
                            HStack {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(.blue)
                                    .frame(width: 20)
                                Text("Lock:")
                                    .font(.subheadline)
                                    .foregroundColor(theme.secondaryTextColor)
                                Spacer()
                                Text("\(Int(autoLockInterval))s")
                                    .font(.subheadline.monospacedDigit().bold())
                                    .foregroundColor(theme.primaryTextColor)
                            }
                        }
                        
                        if autoCloseEnabled {
                            HStack {
                                Image(systemName: "power")
                                    .foregroundColor(.red)
                                    .frame(width: 20)
                                Text("Close:")
                                    .font(.subheadline)
                                    .foregroundColor(theme.secondaryTextColor)
                                Spacer()
                                Text("\(Int(autoCloseInterval)) min")
                                    .font(.subheadline.monospacedDigit().bold())
                                    .foregroundColor(theme.primaryTextColor)
                            }
                        }
                        
                        if autoLockEnabled && autoCloseEnabled {
                            Divider()
                            
                            let closeSeconds = Int(autoCloseInterval) * 60
                            let lockSeconds = Int(autoLockInterval)
                            
                            if closeSeconds <= lockSeconds {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Configuration Warning")
                                            .font(.caption.bold())
                                            .foregroundColor(.orange)
                                        Text("Auto-close will trigger before auto-lock. Consider adjusting intervals.")
                                            .font(.caption)
                                            .foregroundColor(theme.secondaryTextColor)
                                    }
                                }
                                .padding(8)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(6)
                            } else {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Both timers will run simultaneously using a single event monitor")
                                        .font(.caption)
                                        .foregroundColor(theme.secondaryTextColor)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Session Content
    
    private var sessionContent: some View {
        VStack(spacing: 20) {
            // Session Info
            SettingsCard {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Session Management")
                        .font(.headline)
                        .foregroundColor(theme.primaryTextColor)
                    
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("About Sessions")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(theme.primaryTextColor)
                            Text("Session timeout clears encryption keys from memory for security. This is different from auto-lock - session timeout happens even if you're actively using the app.")
                                .font(.caption)
                                .foregroundColor(theme.secondaryTextColor)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Session Timeout")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(theme.primaryTextColor)
                            Spacer()
                            Text("\(Int(configManager.sessionTimeout / 60)) minutes")
                                .font(.subheadline.monospacedDigit())
                                .foregroundColor(theme.secondaryTextColor)
                        }
                        
                        Slider(
                            value: Binding(
                                get: { configManager.sessionTimeout },
                                set: { configManager.sessionTimeout = $0 }
                            ),
                            in: 300...3600,
                            step: 300
                        )
                        
                        HStack {
                            Text("5 min")
                                .font(.caption)
                                .foregroundColor(theme.secondaryTextColor)
                            Spacer()
                            Text("60 min")
                                .font(.caption)
                                .foregroundColor(theme.secondaryTextColor)
                        }
                    }
                }
            }
            
            // Session Actions
            SettingsCard {
                VStack(spacing: 8) {
                    SettingsActionButton(
                        icon: "info.circle",
                        title: "View Session Info",
                        action: { showingSessionDetails = true }
                    )
                    
                    SettingsActionButton(
                        icon: "lock.fill",
                        title: "Force Lock Now",
                        destructive: true,
                        action: {
                            Task{
                                await CryptoHelper.clearKeys()
                            }
                            NotificationCenter.default.post(name: .sessionExpired, object: nil)
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Clipboard Content
    
    private var clipboardContent: some View {
        VStack(spacing: 20) {
            SettingsCard {
                ClipboardSettingsSection()
                    .environmentObject(theme)
            }
        }
    }
    //MARK: - Monitoring
    private var monitoringContent: some View {
        VStack(spacing: 20) {

            // MARK: - Screenshot Detection
            SettingsCard {
                VStack(alignment: .leading, spacing: 20) {

                    HStack(spacing: 10) {
                        Image(systemName: "camera.shutter.button.fill")
                            .font(.title2)
                            .foregroundColor(.orange)
                        Text("Screenshot Detection")
                            .font(.headline)
                            .foregroundColor(theme.primaryTextColor)
                    }

                    Text("Monitor and log screenshot captures")
                        .font(.subheadline)
                        .foregroundColor(theme.secondaryTextColor)

                    Divider()

                    Toggle("Enable Screenshot Detection", isOn: $screenshotDetector.isEnabled)
                        .toggleStyle(.switch)

                    Text("Log when screenshots are taken while app is open")
                        .font(.caption)
                        .foregroundColor(theme.secondaryTextColor)
                        .padding(.leading, 8)

                    if screenshotDetector.isEnabled {
                        Divider()

                        Toggle("Show Notifications", isOn: $screenshotDetector.notificationsEnabled)
                            .toggleStyle(.switch)

                        Text("Display system notification when screenshot is detected")
                            .font(.caption)
                            .foregroundColor(theme.secondaryTextColor)
                            .padding(.leading, 8)

                        if let lastTime = screenshotDetector.lastScreenshotTime {
                            Divider()

                            HStack {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundColor(.secondary)

                                Text("Last screenshot: \(lastTime.formatted())")
                                    .font(.caption)
                                    .foregroundColor(theme.secondaryTextColor)
                            }
                            .padding(12)
                            .background(Color.secondary.opacity(0.05))
                            .cornerRadius(8)
                        }
                    }
                }
            }

            // MARK: - Memory Pressure Monitoring
            SettingsCard {
                VStack(alignment: .leading, spacing: 20) {

                    HStack(spacing: 10) {
                        Image(systemName: "internaldrive")
                            .font(.title2)
                            .foregroundColor(.blue)
                        Text("Memory Pressure Monitoring")
                            .font(.headline)
                            .foregroundColor(theme.primaryTextColor)
                    }

                    Text("Automatically protect data during low memory conditions")
                        .font(.subheadline)
                        .foregroundColor(theme.secondaryTextColor)

                    Divider()

                    Toggle("Enable Memory Monitoring", isOn: $memoryMonitor.isEnabled)
                        .toggleStyle(.switch)

                    Text("Monitor system memory pressure")
                        .font(.caption)
                        .foregroundColor(theme.secondaryTextColor)
                        .padding(.leading, 8)

                    if memoryMonitor.isEnabled {
                        Divider()

                        Toggle("Auto-Lock on Critical Pressure", isOn: $memoryMonitor.autoLockOnPressure)
                            .toggleStyle(.switch)

                        Text("Automatically lock app when memory is critically low")
                            .font(.caption)
                            .foregroundColor(theme.secondaryTextColor)
                            .padding(.leading, 8)

                        Divider()

                        HStack {
                            Image(systemName: memoryMonitor.isUnderPressure
                                  ? "exclamationmark.triangle.fill"
                                  : "checkmark.circle.fill")
                                .foregroundColor(memoryMonitor.isUnderPressure ? .red : .green)

                            Text(memoryMonitor.isUnderPressure
                                 ? "Under memory pressure"
                                 : "Memory OK")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(theme.primaryTextColor)
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }

    
    // MARK: - Backup Content
    
    private var backupContent: some View {
        VStack(spacing: 20) {
            SettingsCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Backup & Restore")
                        .font(.headline)
                        .foregroundColor(theme.primaryTextColor)
                    
                    Text("Export and import your passwords securely")
                        .font(.subheadline)
                        .foregroundColor(theme.secondaryTextColor)
                    
                    Divider()
                    
                    Button {
                        BackupWindowController.open(context: viewContext)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "externaldrive.fill")
                                .font(.title3)
                                .foregroundColor(theme.badgeBackground)
                                .frame(width: 30)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Backup & Restore")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(theme.primaryTextColor)
                                
                                Text("Export or import your passwords")
                                    .font(.caption)
                                    .foregroundColor(theme.secondaryTextColor)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(theme.secondaryTextColor)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - Danger Content
    
    private var dangerContent: some View {
        VStack(spacing: 20) {
            SettingsCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Danger Zone")
                                .font(.headline)
                                .foregroundColor(theme.primaryTextColor)
                            
                            Text("Irreversible destructive actions")
                                .font(.subheadline)
                                .foregroundColor(theme.secondaryTextColor)
                        }
                    }
                    
                    Divider()
                    
                    VStack(spacing: 8) {

                        
                        DangerActionButton(
                            icon: "trash",
                            title: "Clear Local Data",
                            subtitle: "Permanently delete all saved app data from Local storage"
                        ) {
                            //showClearConfirm = .loxl
                        }
                        
                        DangerActionButton(
                            icon: "trash.fill",
                            title: "Delete All App Data",
                            subtitle: "Permanently delete all stored passwords and settings. This cannot be undone."
                        ) {
                            showDeleteConfirm = true
                        }
                    }
                }
            }
        }
    }

    private var passwordPrompt: some View {
        MasterPasswordPrompt { passwordData in
            Task {
                print("🔐 Verifying master password for backend migration...")

                // Convert to SecData
                guard let secureData = SecData(passwordData) else {
                    print("❌ Failed to create secure password data")
                    await MainActor.run {
                        showError = true
                    }
                    return
                }

                enteredPasswordData = secureData

                // Extract raw Data safely BEFORE async call
                let rawData = secureData.withUnsafeBytes { Data($0) }

                // Run async verification
                let isValid = await CryptoHelper.verifyMasterPassword(
                    password: rawData,
                    context: viewContext
                )

                if isValid {
                    print("✅ Password verified successfully")
                    await MainActor.run {
                        showConfirm = true
                    }
                } else {
                    print("❌ Password verification failed")
                    enteredPasswordData?.clear()
                    enteredPasswordData = nil
                    await MainActor.run {
                        showError = true
                    }
                }
            }
        }
        .frame(minWidth: 350, minHeight: 200)
    }

       
    // MARK: - Helper Functions
       
    
    private func loadSecureSettings() async {
        autoLockEnabled = await CryptoHelper.getAutoLockEnabled()
        autoLockInterval = await Double(CryptoHelper.getAutoLockInterval())
       // autoClearClipboard = CryptoHelper.getAutoClearClipboard()
        clearDelay = await Int(CryptoHelper.getClearDelay())
        autoCloseEnabled = await CryptoHelper.getAutoCloseEnabled()
        autoCloseInterval = await Double(CryptoHelper.getAutoCloseInterval())
    }
       
    private func wipeAllAppData() async {
        // 1️⃣ Clear in-memory keys
        await CryptoHelper.clearKeys()
        
        // 2️⃣ Wipe all persistent data
        await CryptoHelper.wipeAllData(context: viewContext)
         CryptoHelper.wipeAllSecureSettings()
        
        // 3️⃣ Remove deprecated UserDefaults keys
        let keysToRemove = [
            "CryptoHelper.StorageBackend.v2",
            "CryptoHelper.failedAttempts.v2"
        ]
        keysToRemove.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        
        // 4️⃣ Delete app support folder
        if let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
           let bundleID = Bundle.main.bundleIdentifier {
            let folder = appSupportURL.appendingPathComponent(bundleID)
            try? FileManager.default.removeItem(at: folder)
        }
        
        // 5️⃣ Notify observers
        await MainActor.run {
            NotificationCenter.default.post(name: .appResetRequired, object: nil)
        }
    }

}
@available(macOS 15.0, *)
extension CryptoHelper {
    static func wipeAllData(context: NSManagedObjectContext) async {
        await clearKeys()
        await MainActor.run {
            clearCurrentStorage()
            wipeAllSecureSettings()
            
            // Clear Core Data
            let requestPasswords: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "PasswordEntry")
            let requestFolders: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "Folder")
            let deletePasswords = NSBatchDeleteRequest(fetchRequest: requestPasswords)
            let deleteFolders = NSBatchDeleteRequest(fetchRequest: requestFolders)
            
            do {
                try context.execute(deletePasswords)
                try context.execute(deleteFolders)
                try context.save()
            } catch {
                context.rollback()
            }
        }
    }
}


// MARK: - Sidebar Button Component

struct SidebarButton: View {
    @EnvironmentObject private var theme: ThemeManager
    let category: SettingsCategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: category.icon)
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? category.iconColor : theme.secondaryTextColor)
                    .frame(width: 24)
                
                Text(category.rawValue)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? theme.primaryTextColor : theme.secondaryTextColor)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isSelected ? category.iconColor.opacity(0.12) : Color.clear
            )
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }
}

// MARK: - Color Palettes

@available(macOS 15.0, *)
private extension SettingsView {
    var backgroundPalette: [Color] {
        [
            .white,
            Color(.systemGray),
            .gray.opacity(0.25),
            .black,
            Color(.sRGB, red: 0.90, green: 0.95, blue: 1.0, opacity: 1.0),
            .blue.opacity(0.25),
            .teal.opacity(0.25),
            Color(.sRGB, red: 0.90, green: 1.0, blue: 0.90, opacity: 1.0),
            .green.opacity(0.25),
            Color(.sRGB, red: 1.0, green: 0.95, blue: 0.90, opacity: 1.0),
            .orange.opacity(0.25),
            Color(.sRGB, red: 0.95, green: 0.90, blue: 1.0, opacity: 1.0),
            .purple.opacity(0.25),
            .pink.opacity(0.25)
        ]
    }

    var selectionPalette: [Color] {
        [
            Color.blue.opacity(0.18),
            Color.green.opacity(0.18),
            Color.orange.opacity(0.18),
            Color.pink.opacity(0.18),
            Color.purple.opacity(0.18),
            Color.red.opacity(0.18),
            Color.teal.opacity(0.18),
            Color.gray.opacity(0.18)
        ]
    }

    var tilePalette: [Color] {
        [
            Color(NSColor.windowBackgroundColor).opacity(0.6),
            Color.gray.opacity(0.15),
            Color.white.opacity(0.08),
            Color.black.opacity(0.06),
            Color.white.opacity(0.12),
            Color.orange.opacity(0.12)
        ]
    }

    var badgePalette: [Color] {
        [
            .red, .orange, .yellow, .green, .teal, .blue, .indigo, .purple, .pink, .gray, Color(NSColor.controlAccentColor)
        ]
    }

    @ViewBuilder
    func swatchPickerRow(title: String, selection: Binding<Color>, palette: [Color]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(theme.secondaryTextColor)
            
            HStack(spacing: 8) {
                ForEach(palette.indices, id: \.self) { idx in
                    let color = palette[idx]
                    let selected = colorsEqual(selection.wrappedValue, color)
                    Button {
                        selection.wrappedValue = color
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(color)
                                .frame(width: 32, height: 26)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                                )
                            if selected {
                                Image(systemName: "checkmark")
                                    .font(.caption2.weight(.bold))
                                    .foregroundColor(contrastColor(for: color))
                                    .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 0)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(selected ? "Selected" : "Choose color")
                }
                Spacer()
            }
        }
    }

    func colorsEqual(_ a: Color, _ b: Color, tolerance: CGFloat = 0.01) -> Bool {
        guard let ca = nsSRGB(a), let cb = nsSRGB(b) else { return false }
        var ra: CGFloat = 0, ga: CGFloat = 0, ba: CGFloat = 0, aa: CGFloat = 0
        var rb: CGFloat = 0, gb: CGFloat = 0, bb: CGFloat = 0, ab: CGFloat = 0
        ca.getRed(&ra, green: &ga, blue: &ba, alpha: &aa)
        cb.getRed(&rb, green: &gb, blue: &bb, alpha: &ab)
        return abs(ra - rb) <= tolerance &&
               abs(ga - gb) <= tolerance &&
               abs(ba - bb) <= tolerance &&
               abs(aa - ab) <= tolerance
    }

    func contrastColor(for color: Color) -> Color {
        guard let c = nsSRGB(color) else { return .white }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance > 0.6 ? .black : .white
    }

    func nsSRGB(_ color: Color) -> NSColor? {
        let base = NSColor(color)
        return base.usingColorSpace(.sRGB) ??
               base.usingColorSpace(.deviceRGB) ??
               base.usingColorSpace(.genericRGB)
    }
}

// MARK: - Reusable UI Components

struct SettingsCard<Content: View>: View {
    @EnvironmentObject private var theme: ThemeManager
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding()
        .background(theme.adaptiveTileBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(theme.isDarkBackground ? Color.white.opacity(0.08) : Color.clear, lineWidth: 1)
        )
    }
}

struct SettingsToggleRow: View {
    @EnvironmentObject private var theme: ThemeManager
    
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.title3)
                    .frame(width: 30)
                
                Toggle(title, isOn: $isOn)
                    .toggleStyle(.switch)
            }
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(theme.secondaryTextColor)
                    .padding(.leading, 42)
            }
        }
    }
}

struct SettingsActionButton: View {
    @EnvironmentObject private var theme: ThemeManager
    
    let icon: String
    let title: String
    var destructive: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(destructive ? .red : theme.badgeBackground)
                    .frame(width: 30)
                
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(theme.primaryTextColor)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(theme.secondaryTextColor)
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

struct DangerActionButton: View {
    @EnvironmentObject private var theme: ThemeManager
    
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(.red)
                    .font(.title3)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(theme.primaryTextColor)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(theme.secondaryTextColor)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(theme.secondaryTextColor)
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

struct PreviewBox: View {
    let color: Color
    let label: String
    var textColor: Color = .primary
    
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(color)
            .frame(width: 70, height: 50)
            .overlay(
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(textColor)
            )
    }
}

// MARK: - Session Details View

@available(macOS 15.0, *)
struct SessionDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeManager
    @State private var sessionInfo: [String: String] = [:]
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Session Details")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(theme.primaryTextColor)
                    
                    Text("Current session information")
                        .font(.caption)
                        .foregroundColor(theme.secondaryTextColor)
                }
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(theme.secondaryTextColor)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(spacing: 20) {
                    SettingsCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Current Session")
                                .font(.headline)
                                .foregroundColor(theme.primaryTextColor)
                            
                            VStack(spacing: 8) {
                                ForEach(Array(sessionInfo.keys.sorted()), id: \.self) { key in
                                    HStack {
                                        Text(key)
                                            .font(.subheadline)
                                            .foregroundColor(theme.secondaryTextColor)
                                        Spacer()
                                        Text(sessionInfo[key] ?? "")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundColor(theme.primaryTextColor)
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                                    .background(Color.secondary.opacity(0.05))
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }
                    
                    SettingsCard {
                        VStack(spacing: 12) {
                            Button {
                                Task{
                                    await loadSessionInfo()
                                }
                            } label: {
                                Label("Refresh Session Info", systemImage: "arrow.clockwise")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            
                            Button {
                                exportSessionLog()
                            } label: {
                                Label("Export Session Log", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(theme.badgeBackground)
                            .disabled(sessionInfo.isEmpty)
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 500, height: 400)
        .onAppear {
            Task{
                await loadSessionInfo()
            }
        }
    }
    
    private func loadSessionInfo() async {
        sessionInfo = await [
            "Status": CryptoHelper.isUnlocked ? "Unlocked" : "Locked",
            "Failed Attempts": "\(await CryptoHelper.failedAttempts)",
            "Has Master Password": CryptoHelper.hasMasterPassword ? "Yes" : "No",
            "Session Start": Date().formatted(.dateTime)
        ]
    }
    
    private func exportSessionLog() {
        let logData = sessionInfo.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "session_log.txt"
        
        if panel.runModal() == .OK, let url = panel.url {
            try? logData.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
