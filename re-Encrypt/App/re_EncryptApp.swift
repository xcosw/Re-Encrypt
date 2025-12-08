/*
// MARK: - Critical Security & Architecture

//import Foundation
import CryptoKit
//import AppKit
import SwiftUI
import UserNotifications
import os.log


// ==========================================
// UNLOCK TOKEN
// ==========================================

final class UnlockToken: Equatable {
    private let id: UUID
    private var keyStorage: SecData?
    private let creationTime: Date
    private let maxLifetime: TimeInterval = 3600 // 1 hour
    
    init() {
        self.id = UUID()
        self.creationTime = Date()
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        self.keyStorage = SecData(keyData)
    }
    
    var isExpired: Bool {
        return Date().timeIntervalSince(creationTime) > maxLifetime
    }
    
    func clear() {
        keyStorage?.clear()
        keyStorage = nil
    }
    
    static func ==(lhs: UnlockToken, rhs: UnlockToken) -> Bool {
        lhs.id == rhs.id
    }
}


// ==========================================
// APP STRUCTURE
// ==========================================

// MARK: - Updated App Structure Using Unified Idle System

@available(macOS 15.0, *)
@main
struct PasswordManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("LockOnExit") private var lockOnExit: Bool = true
    
    // Core state
    @State private var appState: AppState = CryptoHelper.hasMasterPassword ? .locked() : .setup
    @State private var showMaxAttemptsAlert = false
    @State private var showAboutSheet = false
    @State private var isScreenBlurred = false
    @State private var showBanner = false
    
    // Environment
    @Environment(\.scenePhase) private var scenePhase
    private let persistenceController = PersistenceController.shared
    
    // Managers - SIMPLIFIED!
    @StateObject private var securityConfig = SecurityConfigManager.shared
    @StateObject private var theme = ThemeManager()
    @StateObject private var memoryMonitor = MemoryPressureMonitor.shared
    @StateObject private var securityState = SecurityStateManager.shared
    @StateObject private var screenshotDetector = ScreenshotDetectionManager.shared
    @StateObject private var idleController = UnifiedIdleController.shared
    
    // UI Settings
    @AppStorage("Settings.backgroundColorHex") private var settingsBackgroundHex: String = "#F7F8FAFF"
    @AppStorage("Settings.blurMaterial") private var blurMaterialRaw: String = "hudWindow"
    @AppStorage("Settings.transparency") private var transparency: Double = 0.8
    @AppStorage("Settings.useTint") private var useTint: Bool = true
    @AppStorage("Settings.transparencyEnabled") private var transparencyEnabled: Bool = false
    
    init() {
        CryptoHelper.initializeSecurity()
        AppInitializationHelper.initialize()
        setupSecurityMeasures()
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                backgroundView
                
                mainContent
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                    .environmentObject(theme)
                    .environmentObject(memoryMonitor)
                    .environmentObject(securityConfig)
                    .environmentObject(securityState)
                
               
                if let lockTime = idleController.lockCountdown, lockTime > 0 {
                    autoLockWarningOverlay(remainingSeconds: lockTime)
                        .transition(.opacity.combined(with: .scale))
                        .zIndex(998)
                        .id(lockTime)
                }
                
                if let closeTime = idleController.closeCountdown, closeTime > 0 {
                    autoCloseWarningOverlay(remainingSeconds: closeTime)
                        .transition(.opacity.combined(with: .scale))
                        .zIndex(997)
                        .id(closeTime)
                }
                
                if showBanner {
                    SecurityBanner()
                        .zIndex(999)
                }
                
                if isScreenBlurred {
                    SecurityBlurOverlay()
                        .zIndex(1000)
                }
            }
            .tint(theme.badgeBackground)
            .onChange(of: scenePhase) { _, phase in
                Task {
                    await handleScenePhaseChange(phase)
                }
            }
            .onChange(of: appState) { oldValue, newValue in
                handleAppStateChange(from: oldValue, to: newValue)
            }
            .alert("Maximum Attempts Reached", isPresented: $showMaxAttemptsAlert) {
                Button("OK") {
                    showMaxAttemptsAlert = false
                    appState = .setup
                }
            } message: {
                Text("Too many failed unlock attempts. Storage has been cleared for security.")
            }
            .sheet(isPresented: $showAboutSheet) {
                AboutView()
            }
            .onReceive(NotificationCenter.default.publisher(for: .appResetRequired)) { _ in
                handleAppReset()
            }
            .onReceive(NotificationCenter.default.publisher(for: .memoryPressureDetected)) { _ in
                Task {
                    await handleMemoryPressure()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .sessionExpired)) { _ in
                handleSessionExpired()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                Task.detached {
                    await performCleanupOnTermination()
                }
            }
            .onDisappear {
                idleController.stop()
            }
            .onReceive(NotificationCenter.default.publisher(for: .autoLockTriggered)) { _ in
                handleAutoLockTriggered()
            }
            .onReceive(NotificationCenter.default.publisher(for: .autoLockSettingsChanged)) { _ in
                handleIdleSettingsChanged()
            }
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button("About re:Encrypt") {
                    showAboutSheet = true
                }
            }
        }
        .defaultSize(width: 1000, height: 700)
        .environmentObject(screenshotDetector)
    }
    
    // MARK: - Views
    
    @ViewBuilder
    private var backgroundView: some View {
        if transparencyEnabled {
            VisualEffectBlur(
                material: material(from: blurMaterialRaw),
                blendingMode: .behindWindow,
                alphaValue: transparency
            )
            .ignoresSafeArea()
            
            if useTint, let tintColor = color(from: settingsBackgroundHex) {
                tintColor.opacity(0.3)
                    .ignoresSafeArea()
            }
        } else {
            (color(from: settingsBackgroundHex) ?? Color(.windowBackgroundColor))
                .ignoresSafeArea()
        }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        switch appState {
        case .setup:
            CreateMasterPasswordView { passwordData in
                Task { @MainActor in
                    await handleMasterPasswordCreation(passwordData)
                }
            }
            .environmentObject(theme)
            
        case .locked(let reason):
            UnlockView(
                lockReason: reason,
                onUnlock: { enteredData in
                    Task { @MainActor in
                        await handleUnlock(with: enteredData)
                    }
                },
                onRequireSetup: {
                    handleRequireSetup()
                }
            )
            .environment(\.managedObjectContext, persistenceController.container.viewContext)
            .environmentObject(theme)
            .environmentObject(securityConfig)
            
        case .unlocked(var token):
            if token.isExpired {
                Color.clear
                    .onAppear {
                        token.clear()
                        appState = .locked(reason: .tokenExpired)
                    }
            } else {
                ContentView(unlockToken: token)
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                    .environmentObject(memoryMonitor)
                    .environmentObject(theme)
            }
        }
    }
    
    // MARK: - State Handlers
    
    private func handleAppStateChange(from oldState: AppState, to newState: AppState) {
#if DEBUG
        secureLog("🔄 App state changed: \(oldState) -> \(newState)")
#endif
        // 🌟 Stop unified controller
        idleController.stop()
        
        switch newState {
        case .unlocked:
#if DEBUG
            secureLog("✅ App unlocked - starting sessions")
#endif
            securityState.startSession()
            AppInitializationHelper.initializeSecureSettings()
            securityConfig.reload()
            
            // 🌟 Start unified idle monitoring with delay
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay
                await MainActor.run {
                    if case .unlocked = self.appState {
                        self.idleController.start()
                    }
                }
            }
            
        case .locked(let reason):
#if DEBUG
            secureLog("🔒 App locked: \(reason)")
#endif
            securityState.endSession()
            
        case .setup:
#if DEBUG
            secureLog("⚙️ App in setup mode")
#endif
            securityState.endSession()
        }
    }
    
    private func handleMasterPasswordCreation(_ passwordData: Data) async {
        var password = passwordData
        defer { password.secureClear() }
        
        await CryptoHelper.setMasterPassword(password)
        
        if CryptoHelper.biometricUnlockEnabled {
            BiometricManager.shared.storeMasterPasswordSecure(password)
        }
        
        let token = UnlockToken()
        appState = .unlocked(token)
#if DEBUG
        secureLog("Setting up initial secure settings...")
#endif
        AppInitializationHelper.initialize()
        securityConfig.reload()
    }
    
    private func handleUnlock(with enteredData: Data) async {
        var password = enteredData
        defer { password.secureClear() }
        
        let success = await CryptoHelper.unlockMasterPassword(
            password,
            context: persistenceController.container.viewContext
        )
        
        if success {
            if CryptoHelper.biometricUnlockEnabled {
                BiometricManager.shared.storeMasterPasswordSecure(password)
            }
            
            let token = UnlockToken()
            appState = .unlocked(token)
#if DEBUG
            secureLog("Loading secure settings after unlock...")
#endif
            AppInitializationHelper.initializeSecureSettings()
            securityConfig.reload()
            
        } else if CryptoHelper.failedAttempts >= CryptoHelper.maxAttempts {
            CryptoHelper.failedAttempts = 0
            showMaxAttemptsAlert = true
        }
    }
    
    private func handleRequireSetup() {
        CryptoHelper.failedAttempts = 0
        appState = .setup
    }
    
    private func handleAppReset() {
        if case .unlocked(let token) = appState {
            token.clear()
        }
        appState = .setup
        idleController.stop()
    }
    
    private func handleMemoryPressure() async {
#if DEBUG
        secureLog("⚠️ Memory pressure - locking app")
#endif
        CryptoHelper.clearKeys()
        await SecureClipboard.shared.clearClipboard()
        
        if case .unlocked(let token) = appState {
            token.clear()
            appState = .locked(reason: .memoryPressure)
        }
    }
    
    private func handleSessionExpired() {
#if DEBUG
        secureLog("⏰ Session expired - locking")
#endif
        if case .unlocked(let token) = appState {
            token.clear()
            appState = .locked(reason: .sessionTimeout)
        }
    }
    
    private func handleScenePhaseChange(_ phase: ScenePhase) async {
        switch phase {
        case .background, .inactive:
            await SecureClipboard.shared.clearClipboard()
            
            if CryptoHelper.getAutoLockOnBackground() {
#if DEBUG
                secureLog("🔒 [ScenePhase] Locking app (background lock enabled)")
#endif
                CryptoHelper.clearKeys()
                
                await MainActor.run {
                    if case .unlocked(let token) = appState {
                        let t = token
                        t.clear()
                        appState = .locked(reason: .background)
                    }
                }
            } else {
#if DEBUG
                secureLog("ℹ️ [ScenePhase] App in background but lock disabled")
#endif
            }
            
        case .active:
#if DEBUG
            secureLog("✅ [ScenePhase] App became active")
#endif
            CryptoHelper.autoLockIfNeeded()
            
        @unknown default:
            break
        }
    }
    
    private func performCleanupOnTermination() async {
#if DEBUG
        secureLog("🧹 App terminating - secure cleanup")
#endif
        CryptoHelper.clearKeys()
        await SecureClipboard.shared.clearClipboard()
        
        if case .unlocked(let token) = appState {
            token.clear()
        }
        
        if lockOnExit {
            await BiometricManager.shared.clearStoredPasswordSecure()
        }
    }
    
    // MARK: - Event Handlers
    
    private func handleAutoLockTriggered() {
#if DEBUG
        secureLog("🔒 [App] Auto-lock triggered")
#endif
        if case .unlocked(let token) = appState {
            token.clear()
            appState = .locked(reason: .autoLock)
        }
    }
    
    private func handleIdleSettingsChanged() {
#if DEBUG
        secureLog("⚙️ [App] Idle settings changed")
#endif
        if case .unlocked = appState {
            // Restart unified controller with new settings
            idleController.start()
        } else {
            idleController.stop()
        }
    }
    
    // MARK: - Warning Overlays
    
    private func autoLockWarningOverlay(remainingSeconds: Int) -> some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Warning icon
                ZStack {
                    Circle()
                        .fill(.orange.opacity(0.2))
                        .frame(width: 120, height: 120)
                        .scaleEffect(remainingSeconds <= 3 ? 1.1 : 1.0)
                        .animation(
                            remainingSeconds <= 3
                                ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true)
                                : .default,
                            value: remainingSeconds
                        )
                    
                    Image(systemName: "lock.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(remainingSeconds <= 3 ? .red : .orange)
                }
                
                VStack(spacing: 8) {
                    Text("Auto-Lock Warning")
                        .font(.title.bold())
                        .foregroundColor(.white)
                    
                    Text("Locking in \(remainingSeconds) second\(remainingSeconds == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                }
                
                // Countdown
                Text("\(remainingSeconds)")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundColor(remainingSeconds <= 3 ? .red : .white)
                
                Button(action: { idleController.reset() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "hand.raised.fill")
                        Text("I'm Still Here")
                    }
                    .frame(width: 220)
                    .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.white)
                .foregroundColor(.orange)
            }
            .padding(40)
            .background(RoundedRectangle(cornerRadius: 24).fill(.ultraThinMaterial))
            .shadow(color: .orange.opacity(0.4), radius: 40, y: 20)
        }
    }
    
    private func autoCloseWarningOverlay(remainingSeconds: Int) -> some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Critical warning icon
                ZStack {
                    Circle()
                        .fill(.red.opacity(0.2))
                        .frame(width: 120, height: 120)
                        .scaleEffect(remainingSeconds <= 5 ? 1.15 : 1.0)
                        .animation(
                            remainingSeconds <= 5
                                ? .easeInOut(duration: 0.4).repeatForever(autoreverses: true)
                                : .default,
                            value: remainingSeconds
                        )
                    
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.red)
                }
                
                VStack(spacing: 8) {
                    Text("⚠️ AUTO-CLOSE WARNING")
                        .font(.title.bold())
                        .foregroundColor(.red)
                    
                    Text("App will TERMINATE in \(remainingSeconds)s")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text("All unsaved data will be lost!")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                
                // Countdown
                Text("\(remainingSeconds)")
                    .font(.system(size: 86, weight: .bold, design: .rounded))
                    .foregroundColor(.red)
                
                Button(action: { idleController.reset() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "hand.raised.fill")
                        Text("Keep App Open")
                    }
                    .frame(width: 240)
                    .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
                .foregroundColor(.white)
            }
            .padding(40)
            .background(RoundedRectangle(cornerRadius: 24).fill(.ultraThinMaterial))
            .shadow(color: .red.opacity(0.6), radius: 50, y: 20)
        }
    }
    
    // MARK: - Security Setup
    
    private func setupSecurityMeasures() {
        disableMemoryDumping()
        setupTerminationHandler()
        
        if isDebuggerAttached() {
            showSecurityNotification()
        }
    }
    
    private func disableMemoryDumping() {
        var rlim = rlimit(rlim_cur: 0, rlim_max: 0)
        setrlimit(RLIMIT_CORE, &rlim)
#if DEBUG
        secureLog("✅ Core dumps disabled")
#endif
    }
    
    private func setupTerminationHandler() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [self] _ in
            Task.detached {
                await performCleanupOnTermination()
            }
        }
    }
    
    private func isDebuggerAttached() -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        
        let result = name.withUnsafeMutableBufferPointer { namePointer in
            sysctl(namePointer.baseAddress, 4, &info, &size, nil, 0)
        }
        
        return result == 0 && (info.kp_proc.p_flag & P_TRACED) != 0
    }
    
    @MainActor
    private func showSecurityNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Security Alert"
        content.subtitle = "Debugger Detected"
        content.body = "A debugger is attached to this application."
        content.sound = UNNotificationSound.defaultCritical
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Helpers
    
    private func material(from name: String) -> NSVisualEffectView.Material {
        switch name {
        case "popover": return .popover
        case "sidebar": return .sidebar
        case "menu": return .menu
        case "underWindow": return .underWindowBackground
        default: return .hudWindow
        }
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

// MARK: - Secure Logging

private func secureLog(_ message: String, level: OSLogType = .info) {
    #if DEBUG
    if #available(macOS 11.0, *) {
        let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.app.security",
            category: "App"
        )
        switch level {
        case .debug: logger.debug("\(message, privacy: .private)")
        case .info: logger.info("\(message, privacy: .private)")
        case .error: logger.error("\(message, privacy: .private)")
        case .fault: logger.fault("\(message, privacy: .private)")
        default: logger.log("\(message, privacy: .private)")
        }
    } else {
        os_log("%{private}s", type: level, message)
    }
    #endif
}
*/



 // MARK: - Critical Security & Architecture

 //import Foundation
 import CryptoKit
 //import AppKit
 import SwiftUI
 import UserNotifications
 import os.log


 // ==========================================
 // UNLOCK TOKEN
 // ==========================================

 actor UnlockToken: Equatable {
     private let id: UUID
     private var keyStorage: SecData?
     private let creationTime: Date
     private let maxLifetime: TimeInterval = 3600 // 1 hour
     
     init() {
         self.id = UUID()
         self.creationTime = Date()
         let key = SymmetricKey(size: .bits256)
         let keyData = key.withUnsafeBytes { Data($0) }
         self.keyStorage = SecData(keyData)
     }
     
     nonisolated var isExpired: Bool {
         return Date().timeIntervalSince(creationTime) > maxLifetime
     }
    
     func clear()  {
          keyStorage?.clear()
          keyStorage = nil
     }
     
     static func ==(lhs: UnlockToken, rhs: UnlockToken) -> Bool {
         lhs.id == rhs.id
     }
 }


 // ==========================================
 // APP STRUCTURE
 // ==========================================

 // MARK: - Updated App Structure Using Unified Idle System

 @available(macOS 15.0, *)
 @main
 struct PasswordManagerApp: App {
     @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
     @AppStorage("LockOnExit") private var lockOnExit: Bool = true
     
     // Core state
     @State private var appState: AppState = CryptoHelper.hasMasterPassword ? .locked() : .setup
     @State private var showMaxAttemptsAlert = false
     @State private var showAboutSheet = false
     @State private var isScreenBlurred = false
     @State private var showBanner = false
     
     // Environment
     @Environment(\.scenePhase) private var scenePhase
     private let persistenceController = PersistenceController.shared
     
     // Managers - SIMPLIFIED!
     @StateObject private var securityConfig = SecurityConfigManager.shared
     @StateObject private var theme = ThemeManager()
     @StateObject private var memoryMonitor = MemoryPressureMonitor.shared
     @StateObject private var securityState = SecurityStateManager.shared
     @StateObject private var screenshotDetector = ScreenshotDetectionManager.shared
     @StateObject private var idleController = UnifiedIdleController.shared
     
     // UI Settings
     @AppStorage("Settings.backgroundColorHex") private var settingsBackgroundHex: String = "#F7F8FAFF"
     @AppStorage("Settings.blurMaterial") private var blurMaterialRaw: String = "hudWindow"
     @AppStorage("Settings.transparency") private var transparency: Double = 0.8
     @AppStorage("Settings.useTint") private var useTint: Bool = true
     @AppStorage("Settings.transparencyEnabled") private var transparencyEnabled: Bool = false
     
     init() {
         CryptoHelper.initializeSecurity()
         AppInitializationHelper.initialize()
         setupSecurityMeasures()
     }
     
     var body: some Scene {
         WindowGroup {
             ZStack {
                 backgroundView
                 
                 mainContent
                     .environment(\.managedObjectContext, persistenceController.container.viewContext)
                     .environmentObject(theme)
                     .environmentObject(memoryMonitor)
                     .environmentObject(securityConfig)
                     .environmentObject(securityState)
                 
                
                 if let lockTime = idleController.lockCountdown, lockTime > 0 {
                     autoLockWarningOverlay(remainingSeconds: lockTime)
                         .transition(.opacity.combined(with: .scale))
                         .zIndex(998)
                         .id(lockTime)
                 }
                 
                 if let closeTime = idleController.closeCountdown, closeTime > 0 {
                     autoCloseWarningOverlay(remainingSeconds: closeTime)
                         .transition(.opacity.combined(with: .scale))
                         .zIndex(997)
                         .id(closeTime)
                 }
                 
                 if showBanner {
                     SecurityBanner()
                         .zIndex(999)
                 }
                 
                 if isScreenBlurred {
                     SecurityBlurOverlay()
                         .zIndex(1000)
                 }
             }
             .tint(theme.badgeBackground)
             .onChange(of: scenePhase) { _, phase in
                 Task {
                     await handleScenePhaseChange(phase)
                 }
             }
             .onChange(of: appState) { oldValue, newValue in
                 handleAppStateChange(from: oldValue, to: newValue)
             }
             .alert("Maximum Attempts Reached", isPresented: $showMaxAttemptsAlert) {
                 Button("OK") {
                     showMaxAttemptsAlert = false
                     appState = .setup
                 }
             } message: {
                 Text("Too many failed unlock attempts. Storage has been cleared for security.")
             }
             .sheet(isPresented: $showAboutSheet) {
                 AboutView()
             }
             .onReceive(NotificationCenter.default.publisher(for: .appResetRequired)) { _ in
                 Task {
                     await handleAppReset() }
             }
             .onReceive(NotificationCenter.default.publisher(for: .memoryPressureDetected)) { _ in
                 Task {
                     await handleMemoryPressure()
                 }
             }
             .onReceive(NotificationCenter.default.publisher(for: .sessionExpired)) { _ in
                 Task {
                     await
                 handleSessionExpired()}
             }
             .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                 Task.detached {
                     await performCleanupOnTermination()
                 }
             }
             .onDisappear {
                 idleController.stop()
             }
             .onReceive(NotificationCenter.default.publisher(for: .autoLockTriggered)) { _ in
                 Task {
                     await
                     handleAutoLockTriggered() }
             }
             .onReceive(NotificationCenter.default.publisher(for: .autoLockSettingsChanged)) { _ in
                 handleIdleSettingsChanged()
             }
         }
         .windowStyle(HiddenTitleBarWindowStyle())
         .commands {
             CommandGroup(replacing: .newItem) {}
             CommandGroup(replacing: .appInfo) {
                 Button("About re:Encrypt") {
                     showAboutSheet = true
                 }
             }
         }
         .defaultSize(width: 1000, height: 700)
         .environmentObject(screenshotDetector)
     }
     
     // MARK: - Views
     
     @ViewBuilder
     private var backgroundView: some View {
         if transparencyEnabled {
             VisualEffectBlur(
                 material: material(from: blurMaterialRaw),
                 blendingMode: .behindWindow,
                 alphaValue: transparency
             )
             .ignoresSafeArea()
             
             if useTint, let tintColor = color(from: settingsBackgroundHex) {
                 tintColor.opacity(0.3)
                     .ignoresSafeArea()
             }
         } else {
             (color(from: settingsBackgroundHex) ?? Color(.windowBackgroundColor))
                 .ignoresSafeArea()
         }
     }
     
     @ViewBuilder
     private var mainContent: some View {
         switch appState {
         case .setup:
             CreateMasterPasswordView { passwordData in
                 Task { @MainActor in
                     await handleMasterPasswordCreation(passwordData)
                 }
             }
             .environmentObject(theme)
             
         case .locked(let reason):
             UnlockView(
                 lockReason: reason,
                 onUnlock: { enteredData in
                     Task { @MainActor in
                         await handleUnlock(with: enteredData)
                     }
                 },
                 onRequireSetup: {
                     handleRequireSetup()
                 }
             )
             .environment(\.managedObjectContext, persistenceController.container.viewContext)
             .environmentObject(theme)
             .environmentObject(securityConfig)
             
         case .unlocked(let token):
             if token.isExpired {
                 Color.clear
                     .onAppear {
                         Task {
                             await token.clear()}
                         appState = .locked(reason: .tokenExpired)
                     }
             } else {
                 ContentView(unlockToken: token, onRequireSetup: {
                     handleRequireSetup()
                 })
                     .environment(\.managedObjectContext, persistenceController.container.viewContext)
                     .environmentObject(memoryMonitor)
                     .environmentObject(theme)
             }
         }
     }
     
     // MARK: - State Handlers
     
     private func handleAppStateChange(from oldState: AppState, to newState: AppState) {
 #if DEBUG
         secureLog("🔄 App state changed: \(oldState) -> \(newState)")
 #endif
         // 🌟 Stop unified controller
         idleController.stop()
         
         switch newState {
         case .unlocked:
 #if DEBUG
             secureLog("✅ App unlocked - starting sessions")
 #endif
             securityState.startSession()
             AppInitializationHelper.initializeSecureSettings()
             securityConfig.reload()
             
             // 🌟 Start unified idle monitoring with delay
             Task {
                 try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay
                 await MainActor.run {
                     if case .unlocked = self.appState {
                         self.idleController.start()
                     }
                 }
             }
             
         case .locked(let reason):
 #if DEBUG
             secureLog("🔒 App locked: \(reason)")
 #endif
             securityState.endSession()
             
         case .setup:
 #if DEBUG
             secureLog("⚙️ App in setup mode")
 #endif
             securityState.endSession()
         }
     }
     
     private func handleMasterPasswordCreation(_ passwordData: Data) async {
         var password = passwordData
         defer { password.secureClear() }
         
         await CryptoHelper.setMasterPassword(password)
         
         if CryptoHelper.biometricUnlockEnabled {
             BiometricManager.shared.storeMasterPasswordSecure(password)
         }
         
         let token = UnlockToken()
         appState = .unlocked(token)
 #if DEBUG
         secureLog("Setting up initial secure settings...")
 #endif
         AppInitializationHelper.initialize()
         securityConfig.reload()
     }
     
     private func handleUnlock(with enteredData: Data) async {
         var password = enteredData
         defer { password.secureClear() }
         
         let success = await CryptoHelper.unlockMasterPassword(
             password,
             context: persistenceController.container.viewContext
         )
         
         if success {
             if CryptoHelper.biometricUnlockEnabled {
                 BiometricManager.shared.storeMasterPasswordSecure(password)
             }
             
             let token = UnlockToken()
             appState = .unlocked(token)
 #if DEBUG
             secureLog("Loading secure settings after unlock...")
 #endif
             AppInitializationHelper.initializeSecureSettings()
             securityConfig.reload()
             
         } else if CryptoHelper.failedAttempts >= CryptoHelper.maxAttempts {
             CryptoHelper.failedAttempts = 0
             showMaxAttemptsAlert = true
         }
     }
     
     private func handleRequireSetup() {
         CryptoHelper.failedAttempts = 0
         appState = .setup
     }
     
     private func handleAppReset() async {
         if case .unlocked(let token) = appState {
             await token.clear()
         }
         appState = .setup
         idleController.stop()
     }
     
     private func handleMemoryPressure() async {
 #if DEBUG
         secureLog("⚠️ Memory pressure - locking app")
 #endif
         CryptoHelper.clearKeys()
         await SecureClipboard.shared.clearClipboard()
         
         if case .unlocked(let token) = appState {
             await token.clear()
             appState = .locked(reason: .memoryPressure)
         }
     }
     
     private func handleSessionExpired() async{
 #if DEBUG
         secureLog("⏰ Session expired - locking")
 #endif
         if case .unlocked(let token) = appState {
            await token.clear()
             appState = .locked(reason: .sessionTimeout)
         }
     }
     
     private func handleScenePhaseChange(_ phase: ScenePhase) async {
         switch phase {
         case .background, .inactive:
             await SecureClipboard.shared.clearClipboard()
             
             if CryptoHelper.getAutoLockOnBackground() {
 #if DEBUG
                 secureLog("🔒 [ScenePhase] Locking app (background lock enabled)")
 #endif
                 CryptoHelper.clearKeys()
                 
                 await MainActor.run {
                     if case .unlocked(let token) = appState {
                         let t = token
                         Task {
                             await t.clear()
                         }
                         appState = .locked(reason: .background)
                     }
                 }
             } else {
 #if DEBUG
                 secureLog("ℹ️ [ScenePhase] App in background but lock disabled")
 #endif
             }
             
         case .active:
 #if DEBUG
             secureLog("✅ [ScenePhase] App became active")
 #endif
             CryptoHelper.autoLockIfNeeded()
             
         @unknown default:
             break
         }
     }
     
     private func performCleanupOnTermination() async {
 #if DEBUG
         secureLog("🧹 App terminating - secure cleanup")
 #endif
         CryptoHelper.clearKeys()
         await SecureClipboard.shared.clearClipboard()
         
         if case .unlocked(let token) = appState {
             await token.clear()
         }
         
         if lockOnExit {
             await BiometricManager.shared.clearStoredPasswordSecure()
         }
     }
     
     // MARK: - Event Handlers
     
     private func handleAutoLockTriggered() async {
 #if DEBUG
         secureLog("🔒 [App] Auto-lock triggered")
 #endif
         if case .unlocked(let token) = appState {
             await token.clear()
             appState = .locked(reason: .autoLock)
         }
     }
     
     private func handleIdleSettingsChanged() {
 #if DEBUG
         secureLog("⚙️ [App] Idle settings changed")
 #endif
         if case .unlocked = appState {
             // Restart unified controller with new settings
             idleController.start()
         } else {
             idleController.stop()
         }
     }
     
     // MARK: - Warning Overlays
     
     private func autoLockWarningOverlay(remainingSeconds: Int) -> some View {
         ZStack {
             Color.black.opacity(0.6)
                 .ignoresSafeArea()
             
             VStack(spacing: 24) {
                 // Warning icon
                 ZStack {
                     Circle()
                         .fill(.orange.opacity(0.2))
                         .frame(width: 120, height: 120)
                         .scaleEffect(remainingSeconds <= 3 ? 1.1 : 1.0)
                         .animation(
                             remainingSeconds <= 3
                                 ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true)
                                 : .default,
                             value: remainingSeconds
                         )
                     
                     Image(systemName: "lock.fill")
                         .font(.system(size: 56))
                         .foregroundStyle(remainingSeconds <= 3 ? .red : .orange)
                 }
                 
                 VStack(spacing: 8) {
                     Text("Auto-Lock Warning")
                         .font(.title.bold())
                         .foregroundColor(.white)
                     
                     Text("Locking in \(remainingSeconds) second\(remainingSeconds == 1 ? "" : "s")")
                         .font(.subheadline)
                         .foregroundColor(.white.opacity(0.9))
                 }
                 
                 // Countdown
                 Text("\(remainingSeconds)")
                     .font(.system(size: 72, weight: .bold, design: .rounded))
                     .foregroundColor(remainingSeconds <= 3 ? .red : .white)
                 
                 Button(action: { idleController.reset() }) {
                     HStack(spacing: 8) {
                         Image(systemName: "hand.raised.fill")
                         Text("I'm Still Here")
                     }
                     .frame(width: 220)
                     .font(.headline)
                 }
                 .buttonStyle(.borderedProminent)
                 .controlSize(.large)
                 .tint(.white)
                 .foregroundColor(.orange)
             }
             .padding(40)
             .background(RoundedRectangle(cornerRadius: 24).fill(.ultraThinMaterial))
             .shadow(color: .orange.opacity(0.4), radius: 40, y: 20)
         }
     }
     
     private func autoCloseWarningOverlay(remainingSeconds: Int) -> some View {
         ZStack {
             Color.black.opacity(0.7)
                 .ignoresSafeArea()
             
             VStack(spacing: 24) {
                 // Critical warning icon
                 ZStack {
                     Circle()
                         .fill(.red.opacity(0.2))
                         .frame(width: 120, height: 120)
                         .scaleEffect(remainingSeconds <= 5 ? 1.15 : 1.0)
                         .animation(
                             remainingSeconds <= 5
                                 ? .easeInOut(duration: 0.4).repeatForever(autoreverses: true)
                                 : .default,
                             value: remainingSeconds
                         )
                     
                     Image(systemName: "exclamationmark.triangle.fill")
                         .font(.system(size: 56))
                         .foregroundStyle(.red)
                 }
                 
                 VStack(spacing: 8) {
                     Text("⚠️ AUTO-CLOSE WARNING")
                         .font(.title.bold())
                         .foregroundColor(.red)
                     
                     Text("App will TERMINATE in \(remainingSeconds)s")
                         .font(.headline)
                         .foregroundColor(.white)
                     
                     Text("All unsaved data will be lost!")
                         .font(.caption)
                         .foregroundColor(.white.opacity(0.8))
                 }
                 
                 // Countdown
                 Text("\(remainingSeconds)")
                     .font(.system(size: 86, weight: .bold, design: .rounded))
                     .foregroundColor(.red)
                 
                 Button(action: { idleController.reset() }) {
                     HStack(spacing: 8) {
                         Image(systemName: "hand.raised.fill")
                         Text("Keep App Open")
                     }
                     .frame(width: 240)
                     .font(.headline)
                 }
                 .buttonStyle(.borderedProminent)
                 .controlSize(.large)
                 .tint(.red)
                 .foregroundColor(.white)
             }
             .padding(40)
             .background(RoundedRectangle(cornerRadius: 24).fill(.ultraThinMaterial))
             .shadow(color: .red.opacity(0.6), radius: 50, y: 20)
         }
     }
     
     // MARK: - Security Setup
     
     private func setupSecurityMeasures() {
         disableMemoryDumping()
         setupTerminationHandler()
         
         if isDebuggerAttached() {
             showSecurityNotification()
         }
     }
     
     private func disableMemoryDumping() {
         var rlim = rlimit(rlim_cur: 0, rlim_max: 0)
         setrlimit(RLIMIT_CORE, &rlim)
 #if DEBUG
         secureLog("✅ Core dumps disabled")
 #endif
     }
     
     private func setupTerminationHandler() {
         NotificationCenter.default.addObserver(
             forName: NSApplication.willTerminateNotification,
             object: nil,
             queue: .main
         ) { [self] _ in
             Task.detached {
                 await performCleanupOnTermination()
             }
         }
     }
     
     private func isDebuggerAttached() -> Bool {
         var info = kinfo_proc()
         var size = MemoryLayout<kinfo_proc>.stride
         var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
         
         let result = name.withUnsafeMutableBufferPointer { namePointer in
             sysctl(namePointer.baseAddress, 4, &info, &size, nil, 0)
         }
         
         return result == 0 && (info.kp_proc.p_flag & P_TRACED) != 0
     }
     
     @MainActor
     private func showSecurityNotification() {
         let content = UNMutableNotificationContent()
         content.title = "Security Alert"
         content.subtitle = "Debugger Detected"
         content.body = "A debugger is attached to this application."
         content.sound = UNNotificationSound.defaultCritical
         
         let request = UNNotificationRequest(
             identifier: UUID().uuidString,
             content: content,
             trigger: nil
         )
         
         UNUserNotificationCenter.current().add(request)
     }
     
     // MARK: - Helpers
     
     private func material(from name: String) -> NSVisualEffectView.Material {
         switch name {
         case "popover": return .popover
         case "sidebar": return .sidebar
         case "menu": return .menu
         case "underWindow": return .underWindowBackground
         default: return .hudWindow
         }
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

 // MARK: - Secure Logging

 private func secureLog(_ message: String, level: OSLogType = .info) {
     #if DEBUG
     if #available(macOS 11.0, *) {
         let logger = Logger(
             subsystem: Bundle.main.bundleIdentifier ?? "com.app.security",
             category: "App"
         )
         switch level {
         case .debug: logger.debug("\(message, privacy: .private)")
         case .info: logger.info("\(message, privacy: .private)")
         case .error: logger.error("\(message, privacy: .private)")
         case .fault: logger.fault("\(message, privacy: .private)")
         default: logger.log("\(message, privacy: .private)")
         }
     } else {
         os_log("%{private}s", type: level, message)
     }
     #endif
 }


 /*
 // ==========================================
 // 5. APP STRUCTURE
 // ==========================================

     
     // MARK: - Auto-Lock Warning Overlay
        private func autoLockWarningOverlay(remainingSeconds: Int) -> some View {
            ZStack {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.3), value: remainingSeconds)

                VStack(spacing: 24) {
                    // Pulsing warning icon
                    ZStack {
                        Circle()
                            .fill(.red.opacity(0.2))
                            .frame(width: 120, height: 120)
                            .scaleEffect(remainingSeconds <= 3 ? 1.1 : 1.0)
                            .animation(
                                remainingSeconds <= 3
                                    ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true)
                                    : .default,
                                value: remainingSeconds
                            )

                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(remainingSeconds <= 3 ? .red : .orange)
                            .symbolEffect(.pulse)
                            .animation(.easeInOut(duration: 0.3), value: remainingSeconds)
                    }

                    // Title
                    VStack(spacing: 8) {
                        Text("Auto-Lock Warning")
                            .font(.title.bold())
                            .foregroundColor(.white)

                        Text("Locking in \(remainingSeconds) second\(remainingSeconds == 1 ? "" : "s")")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.3), value: remainingSeconds)
                    }

                    // Countdown circle
                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.2), lineWidth: 8)
                            .frame(width: 140, height: 140)

                        let warningDuration = min(20, Int(Double(CryptoHelper.getAutoLockInterval()) / 3))
                        let progress = CGFloat(remainingSeconds) / CGFloat(max(1, warningDuration))
                        
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                remainingSeconds <= 3 ? .red : .orange,
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .frame(width: 140, height: 140)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1.0), value: remainingSeconds)

                        VStack(spacing: 4) {
                            Text("\(remainingSeconds)")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundColor(remainingSeconds <= 3 ? .red : .white)
                                .contentTransition(.numericText(value: Double(remainingSeconds)))
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: remainingSeconds)
                                .scaleEffect(remainingSeconds <= 3 ? 1.15 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: remainingSeconds <= 3)

                            Text("seconds")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }

                    // Stay active button
                    Button(action: { autoLockManager.reset() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "hand.raised.fill")
                            Text("I'm Still Here")
                        }
                        .frame(width: 220)
                        .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.white)
                    .foregroundColor(.red)
                    .scaleEffect(remainingSeconds <= 3 ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: remainingSeconds <= 3)
                }
                .padding(40)
                .background(RoundedRectangle(cornerRadius: 24).fill(.ultraThinMaterial))
                .shadow(
                    color: remainingSeconds <= 3 ? .red.opacity(0.6) : .red.opacity(0.4),
                    radius: remainingSeconds <= 3 ? 50 : 40,
                    y: 20
                )
                .scaleEffect(remainingSeconds <= 3 ? 1.02 : 1.0)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: remainingSeconds)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
     
    
        
     
        
       
    
 }

*/
