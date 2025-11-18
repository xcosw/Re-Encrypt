// MARK: - Critical Security & Architecture Improvements

import Foundation
import CryptoKit
import AppKit
import SwiftUI
import UserNotifications
import os.log
// ==========================================
// 1. IMPROVED UNLOCK TOKEN
// ==========================================

struct UnlockToken: Equatable {
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
    
    mutating func clear() {
        keyStorage?.clear()
        keyStorage = nil
    }
    
    static func ==(lhs: UnlockToken, rhs: UnlockToken) -> Bool {
        lhs.id == rhs.id
    }
}

// ==========================================
// 2. IMPROVED APP STATE WITH BETTER VALIDATION
// ==========================================

/*private enum AppState: Equatable {
    case setup
    case locked(reason: LockReason = .normal)
    case unlocked(UnlockToken)
    
    enum LockReason: Equatable {
        case normal
        case memoryPressure
        case sessionTimeout
        case maxAttempts
        case background
        case tokenExpired
    }
}*/

// ==========================================
// 3. CENTRALIZED AUTO-CLOSE MANAGER
// ==========================================

@MainActor
final class AutoCloseManager: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var remainingSeconds: Int = 0
    
    private var task: Task<Void, Never>?
    private var eventMonitors: [Any] = []
    private var generation: Int = 0
    private let queue = DispatchQueue(label: "autoclose.queue")
    
    func start() {
        guard !isActive else {
            print("⚠️ Auto-close already active")
            return
        }
        
        let enabled = CryptoHelper.getAutoCloseEnabled()
        guard enabled else { return }
        
        stop()
        setupActivityMonitoring()
        startTimer()
    }
    
    func stop() {
        print("🛑 Stopping auto-close")
        task?.cancel()
        task = nil
        isActive = false
        remainingSeconds = 0
        cleanupMonitoring()
    }
    
    func reset() {
        guard isActive else { return }
        print("🔄 Resetting auto-close timer")
        stop()
        start()
    }
    
    private func startTimer() {
        let interval = CryptoHelper.getAutoCloseInterval()
        let seconds = max(60, interval * 60)
        
        generation &+= 1
        let currentGeneration = generation
        
        isActive = true
        remainingSeconds = seconds
        
        print("⏱️ Auto-close timer started: \(interval) minutes")
        
        task = Task {
            while remainingSeconds > 0, !Task.isCancelled, generation == currentGeneration {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if !Task.isCancelled {
                    remainingSeconds -= 1
                }
            }
            
            if !Task.isCancelled, generation == currentGeneration {
                await performAutoClose()
            } else {
                isActive = false
            }
        }
    }
    
    private func performAutoClose() {
        print("⏱️ Auto-close timeout reached - terminating app")
        CryptoHelper.performSecureCleanup()
        NSApplication.shared.terminate(nil)
    }
    
    private func setupActivityMonitoring() {
        cleanupMonitoring()
        
        let eventMask: NSEvent.EventTypeMask = [
            .keyDown, .mouseMoved, .leftMouseDown,
            .rightMouseDown, .scrollWheel
        ]
        
        if let global = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] _ in
            self?.reset()
        } {
            eventMonitors.append(global)
        }
        
        if let local = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            self?.reset()
            return event
        } {
            eventMonitors.append(local)
        }
    }
    
    private func cleanupMonitoring() {
        eventMonitors.forEach { NSEvent.removeMonitor($0) }
        eventMonitors.removeAll()
    }
    
    @MainActor
    deinit {
        cleanupMonitoring()
    }
}

// ==========================================
// 4. SECURITY STATE MANAGER
// ==========================================

@MainActor
final class SecurityStateManager: ObservableObject {
    static let shared = SecurityStateManager()
    
    @Published private(set) var isUnderMemoryPressure = false
    @Published private(set) var hasActiveSession = false
    @Published private(set) var sessionRemainingTime: TimeInterval = 0
    
    private var sessionTimer: Timer?
    
    private init() {
        setupNotificationObservers()
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryPressure),
            name: .memoryPressureDetected,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionExpired),
            name: .sessionExpired,
            object: nil
        )
    }
    
    func startSession() {
        hasActiveSession = true
        updateSessionTimer()
    }
    
    func endSession() {
        hasActiveSession = false
        sessionTimer?.invalidate()
        sessionTimer = nil
        sessionRemainingTime = 0
    }
    
    private func updateSessionTimer() {
        sessionTimer?.invalidate()
        
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let timeout = CryptoHelper.sessionTimeout
            let elapsed = CryptoHelper.getSessionElapsed()
            self.sessionRemainingTime = max(0, timeout - elapsed)
            
            if self.sessionRemainingTime <= 0 {
                self.handleSessionExpired()
            }
        }
    }
    
    @objc private func handleMemoryPressure() {
        isUnderMemoryPressure = true
        endSession()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.isUnderMemoryPressure = false
        }
    }
    
    @objc private func handleSessionExpired() {
        endSession()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// ==========================================
// 5. IMPROVED APP STRUCTURE
// ==========================================

@available(macOS 15.0, *)
@main
struct PasswordManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("LockOnExit") private var lockOnExit: Bool = true
    
    // Core state
    @State private var appState: AppState = CryptoHelper.hasMasterPassword ? .locked() : .setup
    @State private var showMaxAttemptsAlert = false
    @State private var showAboutSheet = false
    
    // Environment
    @Environment(\.scenePhase) private var scenePhase
    private let persistenceController = PersistenceController.shared
    
    // Managers
    @StateObject private var securityConfig = SecurityConfigManager.shared
    @StateObject private var theme = ThemeManager()
    @StateObject private var memoryMonitor = MemoryPressureMonitor.shared
    @StateObject private var autoCloseManager = AutoCloseManager()
    @StateObject private var securityState = SecurityStateManager.shared
    
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
                    .environmentObject(autoCloseManager)
                    .environmentObject(securityState)
            }
            .tint(theme.badgeBackground)
            .onChange(of: scenePhase) { _, phase in
                handleScenePhaseChange(phase)
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
                handleMemoryPressure()
            }
            .onReceive(NotificationCenter.default.publisher(for: .sessionExpired)) { _ in
                handleSessionExpired()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                performCleanupOnTermination()
            }
            .onDisappear {
                autoCloseManager.stop()
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
                handleMasterPasswordCreation(passwordData)
            }
            .environmentObject(theme)
            
        case .locked(let reason):
            UnlockView(
                lockReason: reason,
                onUnlock: { enteredData in
                    handleUnlock(with: enteredData)
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
        print("📊 App state: \(oldState) → \(newState)")
        
        autoCloseManager.stop()
        
        switch newState {
        case .unlocked:
            securityState.startSession()
            // Delay to prevent rapid cycling
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
                if case .unlocked = appState {
                    autoCloseManager.start()
                }
            }
            
        case .locked, .setup:
            securityState.endSession()
        }
    }
    
    private func handleMasterPasswordCreation(_ passwordData: Data) {
        var password = passwordData
        defer { password.secureClear() }
        
        CryptoHelper.setMasterPassword(password)
        
        if CryptoHelper.biometricUnlockEnabled {
            BiometricManager.shared.storeMasterPasswordSecure(password)
        }
        
        let token = UnlockToken()
        appState = .unlocked(token)
        
        print("🔐 Setting up initial secure settings...")
        AppInitializationHelper.setDefaultSettings()
        securityConfig.reload()
    }
    
    private func handleUnlock(with enteredData: Data) {
        var password = enteredData
        defer { password.secureClear() }
        
        let success = CryptoHelper.unlockMasterPassword(
            password,
            context: persistenceController.container.viewContext
        )
        
        if success {
            if CryptoHelper.biometricUnlockEnabled {
                BiometricManager.shared.storeMasterPasswordSecure(password)
            }
            
            let token = UnlockToken()
            appState = .unlocked(token)
            
            print("🔐 Loading secure settings after unlock...")
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
        if case .unlocked(var token) = appState {
            token.clear()
        }
        appState = .setup
        autoCloseManager.stop()
    }
    
    private func handleMemoryPressure() {
        secureLog("⚠️ Memory pressure - locking app")
        CryptoHelper.clearKeys()
        SecureClipboard.shared.clearClipboard()
        
        if case .unlocked(var token) = appState {
            token.clear()
            appState = .locked(reason: .memoryPressure)
        }
    }
    
    private func handleSessionExpired() {
        secureLog("⏰ Session expired - locking")
        
        if case .unlocked(var token) = appState {
            token.clear()
            appState = .locked(reason: .sessionTimeout)
        }
    }
    
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background, .inactive:
            SecureClipboard.shared.clearClipboard()
            
            if CryptoHelper.getAutoLockOnBackground() {
                CryptoHelper.clearKeys()
                if case .unlocked(var token) = appState {
                    token.clear()
                    appState = .locked(reason: .background)
                }
            }
            
        case .active:
            CryptoHelper.autoLockIfNeeded()
            
        @unknown default:
            break
        }
    }
    
    private func performCleanupOnTermination() {
        secureLog("🧹 App terminating - secure cleanup")
        
        CryptoHelper.clearKeys()
        SecureClipboard.shared.clearClipboard()
        
        if case .unlocked(var token) = appState {
            token.clear()
        }
        
        if lockOnExit {
            BiometricManager.shared.clearStoredPasswordSecure()
        }
    }
    
    // MARK: - Security Setup
    
    private func setupSecurityMeasures() {
        disableMemoryDumping()
        setupTerminationHandler()
        setupScreenshotObserver()
        
        if isDebuggerAttached() {
            showSecurityNotification(
                title: "Debugger Detected",
                body: "Please close the debugger before continuing."
            )
        }
    }
    
    private func disableMemoryDumping() {
        var rlim = rlimit(rlim_cur: 0, rlim_max: 0)
        setrlimit(RLIMIT_CORE, &rlim)
        secureLog("✅ Core dumps disabled")
    }
    
    private func setupTerminationHandler() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [self] _ in
            performCleanupOnTermination()
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
    
    private func setupScreenshotObserver() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screencapture.didTakeScreenshot"),
            object: nil,
            queue: .main
        ) { _ in
            showSecurityNotification(
                title: "Screenshot Detected",
                body: "A screenshot was taken while using the app."
            )
            secureLog("⚠️ Screenshot detected")
        }
    }
    
    private func showSecurityNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        center.add(request)
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
