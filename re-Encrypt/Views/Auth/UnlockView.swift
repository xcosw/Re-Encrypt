import SwiftUI
import LocalAuthentication
// MARK: - UnlockView

// ==========================================
// 2. APP STATE WITH VALIDATION
// ==========================================
// MARK: - Lock Reason Enum
 enum AppState: Equatable {
    case setup
    case locked(reason: LockReason = .normal)
    case unlocked(UnlockToken)
    
     enum LockReason : Equatable{
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
             case .normal: return "App Loked Normal"
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
            setupUnlockView()
        }
        .onDisappear {
            cleanup()
        }
    }
    
    // MARK: - Password View
    
    private var passwordView: some View {
        VStack(spacing: 24) {
            // Icon
            ZStack {
                Circle()
                    .fill(theme.badgeBackground.opacity(0.2))
                    .frame(width: 100, height: 100)
                
                Image(systemName: lockIconForReason)
                    .font(.system(size: 48))
                    .foregroundStyle(theme.badgeBackground.gradient)
                    .symbolEffect(.pulse)
            }
            
            // Title and message
            VStack(spacing: 8) {
                Text(lockTitleForReason)
                    .font(.title.bold())
                    .foregroundColor(theme.primaryTextColor)
                
                Text(lockMessageForReason)
                    .font(.subheadline)
                    .foregroundColor(theme.secondaryTextColor)
                    .multilineTextAlignment(.center)
            }
            
            // Password field
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "key.fill")
                        .foregroundColor(theme.secondaryTextColor)
                    
                    SecureField("Master Password", text: $passwordInput)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .focused($isFocused)
                        .onSubmit { attemptPasswordUnlock() }
                        .disabled(lockoutTimeRemaining > 0)
                }
                .padding(12)
                .background(theme.isDarkBackground ? Color.white.opacity(0.08) : Color.primary.opacity(0.06))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isFocused ? theme.badgeBackground : Color.clear, lineWidth: 2)
                )
                
                // Error message
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
                
                // Lockout timer
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
            
            // Unlock button
            Button(action: attemptPasswordUnlock) {
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
            
            // Biometric option
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
                Button(action: attemptBiometricUnlock) {
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
                            // Limit to 6 digits
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
            
            Button(action: verify2FAAndUnlock) {
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
            
            Button(action: {
                show2FAPrompt = false
                tempPasswordForUnlock = nil
                twoFactorCode = ""
                errorMessage = nil
            }) {
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
    
    private func setupUnlockView() {
        failedAttempts = CryptoHelper.failedAttempts
        
        // Auto-trigger biometric if available and preferred
        if CryptoHelper.biometricUnlockEnabled &&
           biometricManager.isBiometricAvailable &&
           biometricManager.isPasswordStored {
            showBiometricPrompt = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                attemptBiometricUnlock()
            }
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
    
    private func attemptPasswordUnlock() {
        guard !passwordInput.isEmpty && lockoutTimeRemaining == 0 else {
            showError("Enter your master password")
            return
        }
        
        isAttemptingUnlock = true
        errorMessage = nil
        biometricError = nil
        
        // Convert to Data
        var passwordData = Data(passwordInput.utf8)
        defer {
            passwordData.secureWipe()
            securelyEraseInput()
        }
        
        // Store for processing
        securePasswordStorage.set(passwordData)
        
        // Do unlock with randomized delay (timing attack mitigation)
        Task { @MainActor in
            let randomDelay = UInt64.random(in: 100_000_000...800_000_000)
            try? await Task.sleep(nanoseconds: randomDelay)
            await performPasswordUnlock()
        }
    }

    
    private func performPasswordUnlock() async {
        defer {
            isAttemptingUnlock = false
        }
        
        do {
            guard let passwordData = securePasswordStorage.get() else {
                showError("Failed to retrieve password")
                return
            }
            
            // Verify password
            guard await CryptoHelper.verifyMasterPassword(password: passwordData, context: viewContext) else {
                handleFailedAttempt()
                return
            }
            
            // Check if 2FA is required
            if TwoFactorAuthManager.shared.isEnabled {
                print("🔐 2FA required after password")
                tempPasswordForUnlock = passwordData
                show2FAPrompt = true
            } else {
                // Complete unlock
                completePasswordUnlock(with: passwordData)
            }
            
        } catch {
            showError("Authentication failed: \(error.localizedDescription)")
            handleFailedAttempt()
        }
    }
    
    private func completePasswordUnlock(with passwordData: Data) {
        defer {
            securePasswordStorage.clear()
        }
        
        print("✅ Unlock successful")
        CryptoHelper.failedAttempts = 0
        onUnlock(passwordData)
    }
    
// MARK: - Biometric Unlock
    
    private func attemptBiometricUnlock() {
        print("Biometric unlock requested")
        biometricAttempted = true
        isBiometricAuthenticating = true
        biometricError = nil
        errorMessage = nil
        
        Task { @MainActor in
            let result = await biometricManager.authenticate()
            self.handleBiometricResult(result)
            self.isBiometricAuthenticating = false
        }
    }
    
    private func handleBiometricResult(_ result: Result<Data, BiometricError>) {
        switch result {
        case .success(let passwordData):
            print("Biometric authentication successful")
            
            do {
                // Securely store password from Secure Enclave
                 securePasswordStorage.set(passwordData)
                
                if TwoFactorAuthManager.shared.isEnabled {
                    print("2FA required after biometric")
                    tempPasswordForUnlock = passwordData
                    showBiometricPrompt = false
                    show2FAPrompt = true
                } else {
                    // Perform unlock with proper async delay + anti-timing
                    Task { @MainActor in
                        // Small random delay to prevent timing attacks
                        let randomDelay = UInt64.random(in: 150_000_000...400_000_000) // 0.15–0.4s
                        try? await Task.sleep(nanoseconds: randomDelay)
                        
                        await self.performBiometricUnlock()
                    }
                }
                
            } catch {
                showError("Failed to process biometric data")
                securePasswordStorage.clear()
            }
            
        case .failure(let error):
            print("Biometric failed: \(error.errorDescription ?? "unknown")")
            biometricError = error
            handleBiometricFailure(error)
        }
    }
    private func performBiometricUnlock() async {
        do {
            guard let secureData = securePasswordStorage.get() else {
                showError("Failed to retrieve secure data")
                securePasswordStorage.clear()
                return
            }
            
            // Verify password
            let unlockResult = await CryptoHelper.unlockMasterPassword(secureData, context: viewContext)
            
            if unlockResult {
                print("✅ Unlock successful via biometric")
                CryptoHelper.failedAttempts = 0
                onUnlock(secureData)
            } else {
                print("❌ Unlock failed with biometric")
                showError("Authentication failed")
                handleFailedAttempt()
            }
            
        } catch {
            showError("Authentication error: \(error.localizedDescription)")
            handleFailedAttempt()
        }
        
        securePasswordStorage.clear()
    }
    
    private func handleBiometricFailure(_ error: BiometricError) {
        securePasswordStorage.clear()
        
        switch error {
        case .cancelled:
            print("User cancelled")
            biometricError = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showBiometricPrompt = false
                isFocused = true
            }
            
        case .fallback, .unavailable:
            print("Fallback to password")
            showBiometricPrompt = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isFocused = true
            }
            
        case .lockout:
            print("Biometric lockout")
            showError("Biometric temporarily locked. Use password.")
            applyLockout()
            showBiometricPrompt = false
            
        case .unknown:
            print("Unknown biometric error")
        }
    }
    
// MARK: - 2FA Verification
    
    private func verify2FAAndUnlock() {
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
        
        // Verify 2FA code
        let verified = TwoFactorAuthManager.shared.verify(code: twoFactorCode, masterPassword: passwordData)
        
        if verified {
            print("✅ 2FA verified")
            CryptoHelper.failedAttempts = 0
            onUnlock(passwordData)
            
            // Cleanup
            tempPasswordForUnlock = nil
            twoFactorCode = ""
        } else {
            showError("Invalid 2FA code")
            handleFailedAttempt()
            twoFactorCode = ""
        }
        
        isAttemptingUnlock = false
    }
    
// MARK: - Failed Attempts & Lockout
    
    private func handleFailedAttempt() {
        CryptoHelper.failedAttempts += 1
        failedAttempts = CryptoHelper.failedAttempts
        
        showError("Incorrect password (\(failedAttempts)/\(CryptoHelper.maxAttempts))")
        NSSound.beep()
        
        if failedAttempts >= CryptoHelper.maxAttempts {
            // Max attempts reached
            CryptoHelper.failedAttempts = 0
            onRequireSetup()
        } else if failedAttempts >= 3 {
            applyLockout()
        }
        
        securePasswordStorage.clear()
    }
    
    private func applyLockout() {
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
    
    // MARK: - UI Helpers
    
    private func switchToBiometric() {
        withAnimation(.easeInOut(duration: 0.3)) {
            showBiometricPrompt = true
            errorMessage = nil
            biometricError = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            attemptBiometricUnlock()
        }
    }
    
    private func switchToPassword() {
        withAnimation(.easeInOut(duration: 0.3)) {
            showBiometricPrompt = false
            biometricError = nil
            errorMessage = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isFocused = true
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
        case .memoryPressure:
            return "exclamationmark.triangle.fill"
        case .sessionTimeout:
            return "clock.fill"
        case .maxAttempts:
            return "xmark.shield.fill"
        case .tokenExpired:
            return "hourglass.bottomhalf.filled"
        case .background:
            return "moon.fill"
        default:
            return "lock.shield.fill"
        }
    }
    
    private var lockTitleForReason: String {
        switch lockReason {
        case .memoryPressure:
            return "Locked - Memory Pressure"
        case .sessionTimeout:
            return "Session Expired"
        case .maxAttempts:
            return "Too Many Attempts"
        case .tokenExpired:
            return "Session Expired"
        case .background:
            return "Auto-Locked"
        default:
            return "App Locked"
        }
    }
    
    private var lockMessageForReason: String {
        switch lockReason {
        case .memoryPressure:
            return "Locked due to system memory pressure"
        case .sessionTimeout:
            return "Your session expired due to inactivity"
        case .maxAttempts:
            return "Account locked after too many failed attempts"
        case .tokenExpired:
            return "Your security token has expired"
        case .background:
            return "App was locked when moved to background"
        default:
            return "Enter your master password to continue"
        }
    }
}
