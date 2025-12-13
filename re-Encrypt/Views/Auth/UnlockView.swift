import SwiftUI
import LocalAuthentication

// MARK: - App State
enum AppState: Equatable {
    case setup
    case locked(reason: LockReason = .normal)
    case unlocked(UnlockToken)
    
    enum LockReason: Equatable {
        case normal
        case manual
        case autoLock
        case sessionTimeout
        case memoryPressure
        case background
        case tokenExpired
        case maxAttempts
        
        var message: String {
            switch self {
            case .normal: return "App Locked"
            case .manual: return "App Locked"
            case .autoLock: return "Locked due to inactivity"
            case .sessionTimeout: return "Session expired"
            case .memoryPressure: return "Locked due to memory pressure"
            case .background: return "Locked in background"
            case .tokenExpired: return "Session token expired"
            case .maxAttempts: return "Too Many Attempts"
            }
        }
    }
}

// MARK: - UnlockView
@available(macOS 15.0, *)
struct UnlockView: View {
    // MARK: - Environment
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var securityConfig: SecurityConfigManager
    
    // MARK: - Callbacks
    let lockReason: AppState.LockReason
    let onUnlock: (Data) -> Void
    let onRequireSetup: () -> Void
    
    // MARK: - State Objects
    @StateObject private var biometricManager = BiometricManager.shared
    @StateObject private var securePasswordStorage = SecurePasswordStorage()
    
    // MARK: - State
    @State private var passwordInput: String = ""
    @State private var twoFactorCode: String = ""
    @State private var errorMessage: String?
    @State private var biometricError: BiometricError?
    @State private var lockoutTimeRemaining: Int = 0
    @State private var failedAttempts: Int = 0
    
    // MARK: - Biometric State
    @State private var showBiometricPrompt = false
    @State private var isBiometricAuthenticating = false
    @State private var biometricAttempted = false
    
    // MARK: - 2FA State
    @State private var show2FAPrompt = false
    @State private var tempPasswordForUnlock: Data?
    
    // MARK: - UI State
    @State private var isAttemptingUnlock = false
    @FocusState private var isFocused: Bool
    @State private var lockoutTask: Task<Void, Never>?
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            if show2FAPrompt {
                twoFactorView
            } else if showBiometricPrompt {
                biometricView
            } else {
                passwordView
            }
        }
        .onAppear {
            Task {
                await setupUnlockView()
            }
        }
        .onDisappear {
            cleanup()
        }
    }
    
    // MARK: - Password View
    
    private var passwordView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(theme.badgeBackground.opacity(0.2))
                    .frame(width: 100, height: 100)
                
                Image(systemName: lockIconForReason)
                    .font(.system(size: 48))
                    .foregroundStyle(theme.badgeBackground.gradient)
                    .symbolEffect(.pulse)
            }
            
            VStack(spacing: 8) {
                Text(lockTitleForReason)
                    .font(.title.bold())
                    .foregroundColor(theme.primaryTextColor)
                
                Text(lockMessageForReason)
                    .font(.subheadline)
                    .foregroundColor(theme.secondaryTextColor)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "key.fill")
                        .foregroundColor(theme.secondaryTextColor)
                    
                    SecureField("Master Password", text: $passwordInput)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .focused($isFocused)
                        .onSubmit {
                            Task {
                                await attemptPasswordUnlock()
                            }
                        }
                        .disabled(lockoutTimeRemaining > 0)
                }
                .padding(12)
                .background(theme.isDarkBackground ? Color.white.opacity(0.08) : Color.primary.opacity(0.06))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isFocused ? theme.badgeBackground : Color.clear, lineWidth: 2)
                )
                
                if let errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .transition(.opacity)
                }
                
                if lockoutTimeRemaining > 0 {
                    HStack {
                        Image(systemName: "clock.fill")
                            .foregroundColor(.orange)
                        Text("Locked for \(lockoutTimeRemaining) seconds")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            .frame(width: 320)
            
            Button {
                Task {
                    await attemptPasswordUnlock()
                }
            } label: {
                HStack {
                    if isAttemptingUnlock {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "lock.open.fill")
                        Text("Unlock")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.badgeBackground)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .frame(width: 320)
            .disabled(isAttemptingUnlock || passwordInput.isEmpty || lockoutTimeRemaining > 0)
            
            if shouldShowBiometricOption {
                VStack(spacing: 8) {
                    Divider().frame(width: 320)
                    
                    Button(action: switchToBiometric) {
                        HStack {
                            Image(systemName: biometricManager.biometricSystemImage())
                            Text("Use \(biometricManager.biometricDisplayName())")
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(theme.badgeBackground)
                    .frame(width: 320)
                    .disabled(lockoutTimeRemaining > 0)
                }
            }
        }
        .padding(40)
        .appBackground()
        .background(in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
    }
    
    // MARK: - Biometric View
    
    private var biometricView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(theme.badgeBackground.opacity(0.2))
                    .frame(width: 100, height: 100)
                
                Image(systemName: biometricManager.biometricSystemImage())
                    .font(.system(size: 48))
                    .foregroundStyle(theme.badgeBackground.gradient)
                    .symbolEffect(.pulse)
            }
            
            VStack(spacing: 8) {
                Text("Biometric Authentication")
                    .font(.title.bold())
                    .foregroundColor(theme.primaryTextColor)
                
                if isBiometricAuthenticating {
                    Text("Authenticating...")
                        .font(.subheadline)
                        .foregroundColor(theme.secondaryTextColor)
                } else if biometricAttempted {
                    Text("Authentication required")
                        .font(.subheadline)
                        .foregroundColor(theme.secondaryTextColor)
                } else {
                    Text("Use \(biometricManager.biometricDisplayName()) to unlock")
                        .font(.subheadline)
                        .foregroundColor(theme.secondaryTextColor)
                }
            }
            
            VStack(spacing: 16) {
                Button {
                    Task {
                        await attemptBiometricUnlock()
                    }
                } label: {
                    HStack {
                        if isBiometricAuthenticating {
                            ProgressView()
                                .scaleEffect(0.8)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: biometricManager.biometricSystemImage())
                            Text("Authenticate")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.badgeBackground)
                .controlSize(.large)
                .frame(width: 320)
                .disabled(isBiometricAuthenticating)
                
                if let biometricError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(biometricError.errorDescription ?? "Authentication failed")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .transition(.opacity)
                }
                
                Divider().frame(width: 320)
                
                Button(action: switchToPassword) {
                    HStack {
                        Image(systemName: "key.fill")
                        Text("Use Password Instead")
                    }
                }
                .buttonStyle(.bordered)
                .tint(theme.badgeBackground)
                .frame(width: 320)
                .disabled(isBiometricAuthenticating)
            }
        }
        .padding(40)
        .appBackground()
        .background(in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
    }
    
    // MARK: - 2FA View
    
    private var twoFactorView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(theme.badgeBackground.opacity(0.2))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(theme.badgeBackground.gradient)
            }
            
            VStack(spacing: 8) {
                Text("Two-Factor Authentication")
                    .font(.title.bold())
                    .foregroundColor(theme.primaryTextColor)
                
                Text("Enter your 6-digit code")
                    .font(.subheadline)
                    .foregroundColor(theme.secondaryTextColor)
            }
            
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "number")
                        .foregroundColor(theme.secondaryTextColor)
                    
                    TextField("000000", text: $twoFactorCode)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: twoFactorCode) { _, newValue in
                            if newValue.count > 6 {
                                twoFactorCode = String(newValue.prefix(6))
                            }
                        }
                }
                .padding(12)
                .background(theme.isDarkBackground ? Color.white.opacity(0.08) : Color.primary.opacity(0.06))
                .cornerRadius(10)
                
                if let errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .frame(width: 320)
            
            Button {
                Task {
                    await verify2FAAndUnlock()
                }
            } label: {
                HStack {
                    if isAttemptingUnlock {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "checkmark.shield.fill")
                        Text("Verify")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.badgeBackground)
            .controlSize(.large)
            .frame(width: 320)
            .disabled(isAttemptingUnlock || twoFactorCode.count != 6)
            
            Button {
                show2FAPrompt = false
                tempPasswordForUnlock = nil
                twoFactorCode = ""
                errorMessage = nil
            } label: {
                Text("Cancel")
            }
            .buttonStyle(.bordered)
            .tint(theme.badgeBackground)
            .frame(width: 320)
        }
        .padding(40)
        .appBackground()
        .background(in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
    }
    
    // MARK: - Setup & Cleanup
    
    private func setupUnlockView() async {
        failedAttempts = await AuthenticationManager.shared.getCurrentAttempts()
        
        if CryptoHelper.biometricUnlockEnabled &&
           biometricManager.isBiometricAvailable &&
           biometricManager.isPasswordStored {
            showBiometricPrompt = true
            try? await Task.sleep(nanoseconds: 500_000_000)
            await attemptBiometricUnlock()
        } else {
            showBiometricPrompt = false
            isFocused = true
        }
    }
    
    private func cleanup() {
        lockoutTask?.cancel()
        lockoutTask = nil
        securePasswordStorage.clear()
        securelyEraseInput()
    }
    
    // MARK: - Password Unlock
    
    private func attemptPasswordUnlock() async {
        guard !passwordInput.isEmpty && lockoutTimeRemaining == 0 else {
            showError("Enter your master password")
            return
        }
        
        isAttemptingUnlock = true
        errorMessage = nil
        biometricError = nil
        
        var passwordData = Data(passwordInput.utf8)
        defer {
            passwordData.secureWipe()
            securelyEraseInput()
        }
        
        securePasswordStorage.set(passwordData)
        
        let randomDelay = UInt64.random(in: 100_000_000...800_000_000)
        try? await Task.sleep(nanoseconds: randomDelay)
        await performPasswordUnlock()
    }
    
    private func performPasswordUnlock() async {
        defer {
            isAttemptingUnlock = false
        }
        
        guard let passwordData = securePasswordStorage.get() else {
            showError("Failed to retrieve password")
            return
        }
        
        let verified = await CryptoHelper.verifyMasterPassword(password: passwordData, context: viewContext)
        
        if verified {
            if TwoFactorAuthManager.shared.isEnabled {
                print("🔐 2FA required after password")
                tempPasswordForUnlock = passwordData
                show2FAPrompt = true
            } else {
                completePasswordUnlock(with: passwordData)
            }
        } else {
            await handleFailedAttempt()
        }
    }
    
    private func completePasswordUnlock(with passwordData: Data) {
        defer {
            securePasswordStorage.clear()
        }
        
        print("✅ Unlock successful")
        Task {
            await AuthenticationManager.shared.resetAttempts()
        }
        onUnlock(passwordData)
    }
    
    // MARK: - Biometric Unlock
    
    private func attemptBiometricUnlock() async {
        print("🔐 Biometric unlock requested")
        biometricAttempted = true
        isBiometricAuthenticating = true
        biometricError = nil
        errorMessage = nil
        
        let result = await biometricManager.authenticate()
        await handleBiometricResult(result)
        isBiometricAuthenticating = false
    }
    
    private func handleBiometricResult(_ result: Result<Data, BiometricError>) async {
        switch result {
        case .success(let passwordData):
            print("✅ Biometric authentication successful")
            securePasswordStorage.set(passwordData)
            
            if TwoFactorAuthManager.shared.isEnabled {
                print("🔐 2FA required after biometric")
                tempPasswordForUnlock = passwordData
                showBiometricPrompt = false
                show2FAPrompt = true
            } else {
                let randomDelay = UInt64.random(in: 150_000_000...400_000_000)
                try? await Task.sleep(nanoseconds: randomDelay)
                await performBiometricUnlock()
            }
            
        case .failure(let error):
            print("❌ Biometric failed: \(error.errorDescription ?? "unknown")")
            biometricError = error
            await handleBiometricFailure(error)
        }
    }
    
    private func performBiometricUnlock() async {
        guard let secureData = securePasswordStorage.get() else {
            showError("Failed to retrieve secure data")
            securePasswordStorage.clear()
            return
        }
        
        let unlockResult = await CryptoHelper.unlockMasterPassword(secureData, context: viewContext)
        
        if unlockResult {
            print("✅ Unlock successful via biometric")
            await AuthenticationManager.shared.resetAttempts()
            onUnlock(secureData)
        } else {
            print("❌ Unlock failed with biometric")
            showError("Authentication failed")
            await handleFailedAttempt()
        }
        
        securePasswordStorage.clear()
    }
    
    private func handleBiometricFailure(_ error: BiometricError) async {
        securePasswordStorage.clear()
        
        switch error {
        case .cancelled:
            print("ℹ️ User cancelled")
            biometricError = nil
            try? await Task.sleep(nanoseconds: 300_000_000)
            showBiometricPrompt = false
            isFocused = true
            
        case .fallback, .unavailable:
            print("ℹ️ Fallback to password")
            showBiometricPrompt = false
            try? await Task.sleep(nanoseconds: 300_000_000)
            isFocused = true
            
        case .lockout:
            print("⚠️ Biometric lockout")
            showError("Biometric temporarily locked. Use password.")
            await applyLockout()
            showBiometricPrompt = false
            
        case .unknown:
            print("❌ Unknown biometric error")
        }
    }
    
    // MARK: - 2FA Verification
    
    private func verify2FAAndUnlock() async {
        guard twoFactorCode.count == 6 else {
            showError("Invalid code length")
            return
        }
        
        guard let passwordData = tempPasswordForUnlock else {
            showError("Authentication expired")
            show2FAPrompt = false
            return
        }
        
        isAttemptingUnlock = true
        
        let verified = await TwoFactorAuthManager.shared.verify(code: twoFactorCode, masterPassword: passwordData)
        
        if verified {
            print("✅ 2FA verified")
            await AuthenticationManager.shared.resetAttempts()
            onUnlock(passwordData)
            
            tempPasswordForUnlock = nil
            twoFactorCode = ""
        } else {
            showError("Invalid 2FA code")
            await handleFailedAttempt()
            twoFactorCode = ""
        }
        
        isAttemptingUnlock = false
    }
    
    // MARK: - Failed Attempts & Lockout
    
    private func handleFailedAttempt() async {
        let wiped = await AuthenticationManager.shared.recordFailedAttempt(context: viewContext)
        failedAttempts = await AuthenticationManager.shared.getCurrentAttempts()
        
        if wiped {
            showError("Maximum attempts reached. All data has been wiped for security.")
            NSSound.beep()
            onRequireSetup()
        } else {
            let maxAttempts = AuthenticationManager.maxAttempts
            showError("Incorrect password (\(failedAttempts)/\(maxAttempts))")
            NSSound.beep()
            
            if failedAttempts >= 3 {
                await applyLockout()
            }
        }
        
        securePasswordStorage.clear()
    }
    
    private func applyLockout() async {
        let backoffTime = await AuthenticationManager.shared.getBackoffTimeRemaining()
        
        if backoffTime > 0 {
            lockoutTimeRemaining = Int(backoffTime)
            showError("Too many attempts. Wait \(lockoutTimeRemaining) seconds.")
            
            lockoutTask = Task {
                while lockoutTimeRemaining > 0 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    await MainActor.run {
                        if lockoutTimeRemaining > 0 {
                            lockoutTimeRemaining -= 1
                        }
                    }
                }
            }
        } else {
            let lockoutDuration = min(30, failedAttempts * 5)
            lockoutTimeRemaining = lockoutDuration
            
            lockoutTask = Task {
                for _ in 0..<lockoutDuration {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    await MainActor.run {
                        if lockoutTimeRemaining > 0 {
                            lockoutTimeRemaining -= 1
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - UI Helpers
    
    private func switchToBiometric() {
        withAnimation(.easeInOut(duration: 0.3)) {
            showBiometricPrompt = true
            errorMessage = nil
            biometricError = nil
        }
        
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await attemptBiometricUnlock()
        }
    }
    
    private func switchToPassword() {
        withAnimation(.easeInOut(duration: 0.3)) {
            showBiometricPrompt = false
            biometricError = nil
            errorMessage = nil
        }
        
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await MainActor.run {
                isFocused = true
            }
        }
    }
    
    private func showError(_ message: String) {
        withAnimation {
            errorMessage = message
        }
    }
    
    private func securelyEraseInput() {
        guard !passwordInput.isEmpty else { return }
        passwordInput = String(repeating: "\0", count: passwordInput.count)
        passwordInput.removeAll()
    }
    
    private var shouldShowBiometricOption: Bool {
        CryptoHelper.biometricUnlockEnabled &&
        biometricManager.isBiometricAvailable &&
        biometricManager.isPasswordStored &&
        lockoutTimeRemaining == 0
    }
    
    // MARK: - Lock Reason Helpers
    
    private var lockIconForReason: String {
        switch lockReason {
        case .memoryPressure: return "exclamationmark.triangle.fill"
        case .sessionTimeout: return "clock.fill"
        case .maxAttempts: return "xmark.shield.fill"
        case .tokenExpired: return "hourglass.bottomhalf.filled"
        case .background: return "moon.fill"
        default: return "lock.shield.fill"
        }
    }
    
    private var lockTitleForReason: String {
        switch lockReason {
        case .memoryPressure: return "Locked - Memory Pressure"
        case .sessionTimeout: return "Session Expired"
        case .maxAttempts: return "Too Many Attempts"
        case .tokenExpired: return "Session Expired"
        case .background: return "Auto-Locked"
        default: return "App Locked"
        }
    }
    
    private var lockMessageForReason: String {
        switch lockReason {
        case .memoryPressure: return "Locked due to system memory pressure"
        case .sessionTimeout: return "Your session expired due to inactivity"
        case .maxAttempts: return "Account locked after too many failed attempts"
        case .tokenExpired: return "Your security token has expired"
        case .background: return "App was locked when moved to background"
        default: return "Enter your master password to continue"
        }
    }
}
