
/*import SwiftUI
import CryptoKit

// MARK: - Apple Passwords Style UnlockView with 2FA

struct UnlockView: View {
    @Environment(\.managedObjectContext) private var viewContext
    var onUnlock: (Data) -> Void
    var onRequireSetup: () -> Void = {}

    @StateObject private var theme = ThemeManager()
    @State private var passwordData = Data()
    @State private var showPassword = false
    @State private var errorMessage: String?
    @State private var shakeOffset: CGFloat = 0
    @FocusState private var isFocused: Bool
    @State private var showMaxAttemptsAlert = false
    
    // Enhanced security states
    @State private var isAttemptingUnlock = false
    @State private var remainingAttempts: Int = 5
    @State private var lockoutTimeRemaining: Int = 0
    @State private var securityWarnings: [String] = []
    
    // Timer for lockout countdown
    @State private var lockoutTimer: Timer?
    
    // Biometric
    @State private var biometricManager = BiometricManager.shared
    @State private var isBiometricAuthenticating = false
    @State private var biometricError: BiometricError?
    @StateObject private var securePasswordStorage = SecurePasswordStorage()
    
    // Auto-trigger state
    @State private var hasAutoTriggered = false
    @State private var showResetButton = false
    
    // 2FA states
    @State private var requires2FA = false
    @State private var show2FAPrompt = false
    @State private var tempPasswordForUnlock: Data?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Blurred background
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                    .ignoresSafeArea()
                
                // Single unified unlock interface
                VStack(spacing: 32) {
                    
                    // Biometric section at top
                    if shouldShowBiometric {
                        biometricSection
                    } else {
                        // Show lock icon if biometric not available
                        lockIconSection
                    }
                    
                    // Title section
                    titleSection
                    
                    // Password input section at bottom
                    passwordInputSection
                    
                    // Attempt counter
                    if lockoutTimeRemaining == 0 {
                        attemptsCounter
                    }
                    
                    // 2FA indicator
                    if TwoFactorAuthManager.shared.isEnabled {
                        twoFactorIndicator
                    }
                    
                    // Security warnings
                    if !securityWarnings.isEmpty {
                        securityWarningsView
                    }
                }
                .padding(40)
                .frame(width: 420)
                .appBackground()
                .background(in: RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $show2FAPrompt) {
            if let passwordData = tempPasswordForUnlock {
                TwoFactorVerificationView(
                    masterPassword: passwordData,
                    onSuccess: {
                        show2FAPrompt = false
                        complete2FAUnlock(with: passwordData)
                    },
                    onCancel: {
                        show2FAPrompt = false
                        tempPasswordForUnlock?.secureWipe()
                        tempPasswordForUnlock = nil
                        CryptoHelper.clearKey()
                        isAttemptingUnlock = false
                    }
                )
                .environmentObject(theme)
            }
        }
        .onAppear {
            print("[UnlockView] ========== ON APPEAR ==========")
            setupSecurityEnvironment()
            
            // Force refresh biometric status
            biometricManager.checkBiometricAvailability()
            biometricManager.checkIfPasswordStored()
            
            // Check if 2FA is enabled
            requires2FA = TwoFactorAuthManager.shared.isEnabled
            
            // Slight delay to ensure state is updated
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                print("[UnlockView] Should show biometric: \(self.shouldShowBiometric)")
                print("[UnlockView] 2FA enabled: \(self.requires2FA)")
                
                if self.shouldShowBiometric && !self.hasAutoTriggered {
                    print("[UnlockView] Auto-triggering biometric...")
                    self.hasAutoTriggered = true
                    self.attemptBiometricUnlock()
                }
            }
        }
        .onDisappear {
            cleanupSecurityEnvironment()
        }
        .alert("Maximum Attempts Reached", isPresented: $showMaxAttemptsAlert) {
            Button("Understand") {
                showMaxAttemptsAlert = false
                passwordData.secureWipe()
            }
        } message: {
            Text("Too many failed unlock attempts. All data has been securely wiped for your protection.")
                .foregroundColor(theme.primaryTextColor)
        }
    }

    // MARK: - Computed property to determine if biometric should show

    private var shouldShowBiometric: Bool {
        biometricManager.isBiometricAvailable &&
        biometricManager.isPasswordStored &&
        lockoutTimeRemaining == 0
    }

    // MARK: - 2FA Indicator
    
    private var twoFactorIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundColor(.green)
            Text("Two-factor authentication enabled")
                .font(.caption)
                .foregroundColor(theme.secondaryTextColor)
        }
    }
    
    // MARK: - Biometric Section (Apple Passwords Style)

    private var biometricSection: some View {
        VStack(spacing: 16) {
            // Biometric icon with ring
            ZStack {
                // Outer ring
                Circle()
                    .stroke(theme.badgeBackground.opacity(0.2), lineWidth: 3)
                    .frame(width: 100, height: 100)
                
                // Animated ring when authenticating
                if isBiometricAuthenticating {
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(theme.badgeBackground, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))
                        .rotationEffect(.degrees(isBiometricAuthenticating ? 360 : 0))
                        .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isBiometricAuthenticating)
                }
                
                // Inner circle background
                Circle()
                    .fill(isBiometricAuthenticating ? theme.badgeBackground.opacity(0.15) : theme.badgeBackground.opacity(0.1))
                    .frame(width: 90, height: 90)
                
                // Biometric icon
                Image(systemName: biometricManager.biometricSystemImage())
                    .font(.system(size: 40))
                    .foregroundStyle(theme.badgeBackground.gradient)
                    .symbolEffect(.pulse, isActive: !isBiometricAuthenticating)
            }
            .onTapGesture {
                if !isBiometricAuthenticating && !isAttemptingUnlock {
                    attemptBiometricUnlock()
                }
            }
            
            // Biometric prompt text
            if isBiometricAuthenticating {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Authenticating...")
                        .font(.subheadline)
                }
                .foregroundColor(theme.secondaryTextColor)
            } else {
                Button(action: attemptBiometricUnlock) {
                    HStack(spacing: 6) {
                        Image(systemName: biometricManager.biometricSystemImage())
                            .font(.caption)
                        Text("Touch sensor or click to use \(biometricManager.biometricDisplayName())")
                            .font(.subheadline)
                    }
                    .foregroundColor(theme.badgeBackground)
                }
                .buttonStyle(.plain)
                .disabled(isBiometricAuthenticating || isAttemptingUnlock)
            }
            
            // Biometric error
            if let error = biometricError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text(error.errorDescription ?? "Authentication failed")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                .transition(.opacity.combined(with: .scale))
            }
        }
    }
    
    // MARK: - Lock Icon Section (Fallback)
    
    private var lockIconSection: some View {
        ZStack {
            Circle()
                .fill(lockoutTimeRemaining > 0 ? Color.red.opacity(0.2) : theme.badgeBackground.opacity(0.2))
                .frame(width: 100, height: 100)
            
            Image(systemName: lockoutTimeRemaining > 0 ? "lock.trianglebadge.exclamationmark" : "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(lockoutTimeRemaining > 0 ? Color.red.gradient : theme.badgeBackground.gradient)
                .symbolEffect(.pulse)
        }
    }
    
    // MARK: - Title Section
    
    private var titleSection: some View {
        VStack(spacing: 8) {
            Text(lockoutTimeRemaining > 0 ? "Account Temporarily Locked" : "Unlock Password Manager")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .foregroundColor(theme.primaryTextColor)
            
            if lockoutTimeRemaining > 0 {
                Text("Wait \(lockoutTimeRemaining) seconds")
                    .font(.subheadline)
                    .foregroundColor(.red)
            } else {
                Text("Enter your master password")
                    .font(.subheadline)
                    .foregroundColor(theme.secondaryTextColor)
            }
        }
    }
    
    // MARK: - Password Input Section
    
    private var passwordInputSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .foregroundColor(theme.secondaryTextColor)
                    .font(.body)
                
                SecurePasswordField(
                    passwordData: $passwordData,
                    showPassword: $showPassword,
                    isEnabled: lockoutTimeRemaining == 0 && !isAttemptingUnlock,
                    onSubmit: {
                        if lockoutTimeRemaining == 0 && !isAttemptingUnlock {
                            attemptPasswordUnlock()
                        }
                    }
                )
                .focused($isFocused)
                .foregroundColor(theme.primaryTextColor)
                
                Button(action: { showPassword.toggle() }) {
                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(theme.secondaryTextColor)
                }
                .buttonStyle(.plain)
                .disabled(lockoutTimeRemaining > 0)
            }
            .padding(14)
            .background(
                theme.isDarkBackground
                    ? Color.white.opacity(0.08)
                    : Color.primary.opacity(0.06)
            )
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isFocused ? theme.badgeBackground : Color.clear, lineWidth: 2)
            )
            .offset(x: shakeOffset)
            
            if let error = errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .transition(.opacity.combined(with: .scale))
            }
            
            // Unlock button
            Button(action: attemptPasswordUnlock) {
                HStack {
                    if isAttemptingUnlock {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "arrow.right.circle.fill")
                        Text("Unlock")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.badgeBackground)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(passwordData.isEmpty || lockoutTimeRemaining > 0 || isAttemptingUnlock)
        }
    }
    
    // MARK: - Attempts Counter
    
    private var attemptsCounter: some View {
        Text("Attempts remaining: \(max(0, 5 - CryptoHelper.failedAttempts))")
            .font(.caption)
            .foregroundColor(theme.secondaryTextColor)
    }
    
    // MARK: - Security Warnings View
    
    private var securityWarningsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Security Alerts")
                    .font(.caption.bold())
                    .foregroundColor(.red)
            }
            
            ForEach(securityWarnings, id: \.self) { warning in
                HStack(alignment: .top, spacing: 4) {
                    Text("•")
                        .foregroundColor(theme.secondaryTextColor)
                    Text(warning)
                        .font(.caption2)
                        .foregroundColor(theme.secondaryTextColor)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.5))
        .cornerRadius(10)
    }
    
    // MARK: - Biometric Unlock
    
    private func attemptBiometricUnlock() {
        print("[UnlockView] Biometric unlock requested")
        isBiometricAuthenticating = true
        biometricError = nil
        errorMessage = nil
        
        biometricManager.authenticate { [self] result in
            self.isBiometricAuthenticating = false
            
            switch result {
            case .success(let passwordData):
                print("[UnlockView] ✅ Biometric authentication successful")
                
                // Store in secure storage during processing
                self.securePasswordStorage.set(passwordData)
                
                // Check if 2FA is required
                if TwoFactorAuthManager.shared.isEnabled {
                    print("[UnlockView] 2FA required after biometric")
                    self.tempPasswordForUnlock = passwordData
                    self.show2FAPrompt = true
                } else {
                    // Use the secure storage for unlock
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.performBiometricUnlock()
                    }
                }
                
            case .failure(let error):
                print("[UnlockView] ❌ Biometric failed: \(error.errorDescription ?? "unknown")")
                self.biometricError = error
                self.handleBiometricFailure(error)
            }
        }
    }
    
    private func performBiometricUnlock() {
        guard let secureData = securePasswordStorage.get() else {
            showError("Failed to retrieve secure password data")
            securePasswordStorage.clear()
            return
        }
        
        // Verify the password with CryptoHelper
        let unlockResult = CryptoHelper.unlockMasterPassword(secureData, context: viewContext)
        
        if unlockResult {
            print("[UnlockView] ✅ Unlock successful via biometric")
            CryptoHelper.failedAttempts = 0
            onUnlock(secureData)
        } else {
            print("[UnlockView] ❌ Unlock failed even with correct biometric")
            showError("Authentication failed. Please try again.")
            handleFailedAttempt()
        }
        
        // Clear secure storage immediately after use
        securePasswordStorage.clear()
    }
    
    private func handleBiometricFailure(_ error: BiometricError) {
        print("[UnlockView] handleBiometricFailure: \(error.errorDescription ?? "unknown")")
        
        // Clear any stored data on failure
        securePasswordStorage.clear()
        
        switch error {
        case .cancelled:
            print("[UnlockView] User cancelled - focusing password field")
            biometricError = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isFocused = true
            }
            
        case .fallback, .unavailable:
            print("[UnlockView] Fallback to password entry")
            biometricError = error
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isFocused = true
            }
            
        case .lockout:
            print("[UnlockView] Biometric lockout")
            biometricError = error
            applyLockout()
            
        case .unknown:
            print("[UnlockView] Unknown error")
            biometricError = error
        }
    }
    
    // MARK: - Password Unlock
    
    private func attemptPasswordUnlock() {
        guard !passwordData.isEmpty && lockoutTimeRemaining == 0 else {
            showError("Enter your master password")
            return
        }
        
        isAttemptingUnlock = true
        errorMessage = nil
        biometricError = nil
        
        // Store in secure storage during processing
        securePasswordStorage.set(passwordData)
        
        // Add processing delay for security
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            performPasswordUnlock()
        }
    }
    
    private func performPasswordUnlock() {
        defer {
            securePasswordStorage.clear()
        }
        
        // Get data from secure storage or use passwordData
        guard let dataToUse = securePasswordStorage.get() else {
            showError("Failed to process password")
            isAttemptingUnlock = false
            return
        }
        
        // First verify the master password
        guard CryptoHelper.verifyMasterPassword(password: dataToUse, context: viewContext) else {
            isAttemptingUnlock = false
            handleFailedAttempt()
            return
        }
        
        // Check if 2FA is required
        if TwoFactorAuthManager.shared.isEnabled {
            print("[UnlockView] 2FA required after password")
            tempPasswordForUnlock = dataToUse
            isAttemptingUnlock = false
            show2FAPrompt = true
        } else {
            // No 2FA, complete unlock
            completePasswordUnlock(with: dataToUse)
        }
    }
    
    private func completePasswordUnlock(with passwordData: Data) {
        let unlockResult = CryptoHelper.unlockMasterPassword(passwordData, context: viewContext)
        
        if unlockResult {
            print("[UnlockView] ✅ Password unlock successful")
            CryptoHelper.failedAttempts = 0
            onUnlock(passwordData)
        } else {
            handleFailedAttempt()
        }
        
        // Clear password
        self.passwordData.secureWipe()
        isAttemptingUnlock = false
    }
    
    private func complete2FAUnlock(with passwordData: Data) {
        // 2FA was successful, now complete the unlock
        let unlockResult = CryptoHelper.unlockMasterPassword(passwordData, context: viewContext)
        
        if unlockResult {
            print("[UnlockView] ✅ 2FA unlock successful")
            CryptoHelper.failedAttempts = 0
            onUnlock(passwordData)
        } else {
            showError("Unlock failed after 2FA verification")
            handleFailedAttempt()
        }
        
        // Clean up
        tempPasswordForUnlock?.secureWipe()
        tempPasswordForUnlock = nil
        self.passwordData.secureWipe()
    }
    
    private func handleFailedAttempt() {
        if !CryptoHelper.hasMasterPassword {
            // No master password exists, trigger setup
            CryptoHelper.clearCurrentStorage()
            CryptoHelper.wipeAllData(context: viewContext)
            CryptoHelper.failedAttempts = 0
            onRequireSetup()
            showMaxAttemptsAlert = true
            return
        }
        
        // Update attempt counter
        remainingAttempts = max(0, 5 - CryptoHelper.failedAttempts)
        
        if CryptoHelper.failedAttempts >= 5 {
            // Maximum attempts reached
            CryptoHelper.clearCurrentStorage()
            CryptoHelper.wipeAllData(context: viewContext)
            CryptoHelper.failedAttempts = 0
            onRequireSetup()
            showMaxAttemptsAlert = true
        } else {
            // Show error and apply lockout
            showError("Incorrect password. \(remainingAttempts) attempts remaining.")
            shake()
            applyLockout()
        }
    }
    
    private func applyLockout() {
        let attempts = CryptoHelper.failedAttempts
        let lockoutDuration = min(Int(pow(2.0, Double(attempts - 1))), 60) // Max 60 seconds
        
        lockoutTimeRemaining = lockoutDuration
        
        lockoutTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if lockoutTimeRemaining > 0 {
                lockoutTimeRemaining -= 1
            } else {
                timer.invalidate()
                lockoutTimer = nil
            }
        }
    }
    
    private func updateLockoutStatus() {
        // Check if there should be an active lockout
        let attempts = CryptoHelper.failedAttempts
        if attempts > 0 && attempts < 5 {
            applyLockout()
        }
    }
    
    private func showError(_ message: String) {
        withAnimation(.easeInOut(duration: 0.3)) {
            errorMessage = message
        }
    }
    
    private func shake() {
        withAnimation(.linear(duration: 0.05).repeatCount(6, autoreverses: true)) {
            shakeOffset = 10
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            shakeOffset = 0
        }
    }
    
    // MARK: - Security Setup and Cleanup
    
    private func setupSecurityEnvironment() {
        print("[UnlockView] setupSecurityEnvironment called")
        
        // Refresh biometric availability and check for stored password
        biometricManager.checkBiometricAvailability()
        
        // Check if password is stored
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.biometricManager.checkIfPasswordStored()
            print("[UnlockView] isPasswordStored: \(self.biometricManager.isPasswordStored)")
            print("[UnlockView] isBiometricAvailable: \(self.biometricManager.isBiometricAvailable)")
        }
        
        // Check for security warnings
        checkSecurityWarnings()
        
        // Set up UI focus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.isFocused = true
        }
        
        // Check current lockout status
        updateLockoutStatus()
        
        // Update remaining attempts
        remainingAttempts = max(0, 5 - CryptoHelper.failedAttempts)
    }
    
    private func cleanupSecurityEnvironment() {
        lockoutTimer?.invalidate()
        passwordData.secureWipe()
        tempPasswordForUnlock?.secureWipe()
        tempPasswordForUnlock = nil
        securePasswordStorage.clear()
    }
    
    private func checkSecurityWarnings() {
        securityWarnings.removeAll()
        
        // Check for debugging
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        
        if sysctl(&mib, 4, &info, &size, nil, 0) == 0 {
            if (info.kp_proc.p_flag & P_TRACED) != 0 {
                securityWarnings.append("Debugger detected")
            }
        }
        
        // Check for development build
        #if DEBUG
        securityWarnings.append("Development build - not for production use")
        #endif
    }
}

// MARK: - Enhanced Secure Password Field

private struct SecurePasswordField: NSViewRepresentable {
    @Binding var passwordData: Data
    @Binding var showPassword: Bool
    let isEnabled: Bool
    var onSubmit: () -> Void = {}
    
    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        context.coordinator.setup(container: container, onSubmit: onSubmit)
        return container
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(showPassword: showPassword, isEnabled: isEnabled)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(passwordData: $passwordData)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var passwordData: Data
        private var secureField: NSSecureTextField!
        private var plainField: NSTextField!
        private var container: NSView!
        private var lastUpdate = Date()
        private var onSubmit: () -> Void = {}
        private var secureStorage: SecData?
        
        init(passwordData: Binding<Data>) {
            self._passwordData = passwordData
            super.init()
        }
        
        func setup(container: NSView, onSubmit: @escaping () -> Void) {
            self.container = container
            self.onSubmit = onSubmit
            
            secureField = NSSecureTextField()
            secureField.isBezeled = false
            secureField.drawsBackground = false
            secureField.focusRingType = .none
            secureField.delegate = self
            secureField.font = NSFont.systemFont(ofSize: 14)
            secureField.placeholderString = "Enter master password"
            
            plainField = NSTextField()
            plainField.isBezeled = false
            plainField.drawsBackground = false
            plainField.focusRingType = .none
            plainField.delegate = self
            plainField.font = NSFont.systemFont(ofSize: 14)
            plainField.placeholderString = "Enter master password"
            
            container.addSubview(secureField)
            container.addSubview(plainField)
            
            setupConstraints()
            update(showPassword: false, isEnabled: true)
        }
        
        private func setupConstraints() {
            [secureField, plainField].forEach {
                $0?.translatesAutoresizingMaskIntoConstraints = false
            }
            
            NSLayoutConstraint.activate([
                secureField.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                secureField.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                secureField.topAnchor.constraint(equalTo: container.topAnchor),
                secureField.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                secureField.heightAnchor.constraint(equalToConstant: 28),
                
                plainField.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                plainField.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                plainField.topAnchor.constraint(equalTo: container.topAnchor),
                plainField.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                plainField.heightAnchor.constraint(equalToConstant: 28)
            ])
        }
        
        func update(showPassword: Bool, isEnabled: Bool) {
            secureField.isHidden = showPassword
            plainField.isHidden = !showPassword
            secureField.isEnabled = isEnabled
            plainField.isEnabled = isEnabled
            
            let alpha: CGFloat = isEnabled ? 1.0 : 0.5
            secureField.alphaValue = alpha
            plainField.alphaValue = alpha
        }
        
        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            
            let now = Date()
            guard now.timeIntervalSince(lastUpdate) > 0.1 else { return }
            lastUpdate = now
            
            let string = field.stringValue
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                self.secureStorage?.clear()
                if let data = string.data(using: .utf8) {
                    self.secureStorage = SecData(data)
                }
                
                self.passwordData.secureWipe()
                self.passwordData = Data(string.utf8)
                
                if field === self.secureField {
                    self.plainField.stringValue = string
                } else {
                    self.secureField.stringValue = string
                }
            }
        }
        
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onSubmit()
                return true
            }
            return false
        }
        
        func controlTextDidEndEditing(_ obj: Notification) {
            NSPasteboard.general.clearContents()
        }
        
        deinit {
            secureStorage?.clear()
            secureStorage = nil
        }
    }
}
*/

// MARK: - UnlockView Complete Implementation with Security Improvements

 enum AppState: Equatable {
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
}

import SwiftUI
import LocalAuthentication

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
            
            // Reset option
            if CryptoHelper.failedAttempts >= 3 {
                VStack(spacing: 8) {
                    Divider().frame(width: 320)
                    
                    Button(action: {
                        onRequireSetup()
                    }) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset Password")
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .frame(width: 320)
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
            passwordData.resetBytes(in: 0..<passwordData.count)
            securelyEraseInput()
        }
        
        // Store temporarily for processing
        do {
            try securePasswordStorage.set(passwordData)
        } catch {
            showError("Failed to process password")
            isAttemptingUnlock = false
            return
        }
        
        // Add security delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            performPasswordUnlock()
        }
    }
    
    private func performPasswordUnlock() {
        defer {
            isAttemptingUnlock = false
        }
        
        do {
            guard let passwordData = try securePasswordStorage.get() else {
                showError("Failed to retrieve password")
                return
            }
            
            // Verify password
            guard CryptoHelper.verifyMasterPassword(password: passwordData, context: viewContext) else {
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
        print("🔐 Biometric unlock requested")
        biometricAttempted = true
        isBiometricAuthenticating = true
        biometricError = nil
        errorMessage = nil
        
        biometricManager.authenticate { result in
            DispatchQueue.main.async {
                self.isBiometricAuthenticating = false
                self.handleBiometricResult(result)
            }
        }
    }
    
    private func handleBiometricResult(_ result: Result<Data, BiometricError>) {
        switch result {
        case .success(let passwordData):
            print("✅ Biometric authentication successful")
            
            do {
                // Store temporarily
                try securePasswordStorage.set(passwordData)
                
                // Check if 2FA is required
                if TwoFactorAuthManager.shared.isEnabled {
                    print("🔐 2FA required after biometric")
                    tempPasswordForUnlock = passwordData
                    showBiometricPrompt = false
                    show2FAPrompt = true
                } else {
                    // Verify and unlock
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.performBiometricUnlock()
                    }
                }
            } catch {
                showError("Failed to process biometric data")
                securePasswordStorage.clear()
            }
            
        case .failure(let error):
            print("❌ Biometric failed: \(error.errorDescription ?? "unknown")")
            biometricError = error
            handleBiometricFailure(error)
        }
    }
    
    private func performBiometricUnlock() {
        do {
            guard let secureData = try securePasswordStorage.get() else {
                showError("Failed to retrieve secure data")
                securePasswordStorage.clear()
                return
            }
            
            // Verify password
            let unlockResult = CryptoHelper.unlockMasterPassword(secureData, context: viewContext)
            
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
