import SwiftUI
import CryptoKit

// MARK: - 2FA Setup After Password View

@available(macOS 15.0, *)
struct TwoFactorSetupAfterPasswordView: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.dismiss) private var dismiss
    
    let masterPassword: Data
    let onComplete: () -> Void
    let onSkip: () -> Void
    
    @State private var setupComplete = false
    
    var body: some View {
        ZStack {
            theme.backgroundColor.ignoresSafeArea()
            
            VStack(spacing: 20) {
                if setupComplete {
                    completionView
                } else {
                    TwoFactorSetupView(onSetupComplete: {
                        setupComplete = true
                    })
                    .environmentObject(theme)
                }
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { onSkip() }
                        .foregroundColor(theme.primaryTextColor)
                }
            }
        }
    }
    
    private var completionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(theme.badgeBackground)
            
            Text("Setup Complete!")
                .font(.title.bold())
                .foregroundColor(theme.primaryTextColor)
            
            Text("Your password manager is now secured with 2FA")
                .font(.subheadline)
                .foregroundColor(theme.secondaryTextColor)
            
            Button("Continue") { onComplete() }
                .buttonStyle(.borderedProminent)
                .tint(theme.badgeBackground)
                .controlSize(.large)
        }
        .padding(40)
        .background(theme.tileBackground)
        .cornerRadius(16)
        .shadow(radius: 10)
    }
}

// MARK: - Create Master Password View

@available(macOS 15.0, *)
struct CreateMasterPasswordView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var theme: ThemeManager
    @State private var newPasswordInput = ""
    @State private var confirmPasswordInput = ""
    @State private var showPassword = false
    @State private var errorMessage: String?
    @State private var passwordStrength: Double = 0.0
    @State private var strengthColor: Color = .red
    @State private var strengthText: String = "Very Weak"
    @State private var isCreatingPassword = false
    @State private var showWeakPasswordAlert = false
    
    // 2FA setup states
    @State private var show2FASetup = false
    @State private var enable2FA = false
    @State private var passwordCreated = false
    @State private var createdPasswordData: Data?
    
    @FocusState private var focusedField: Field?
    
    @State private var securityTips: [String] = []
    
    var onComplete: (Data) -> Void
    
    enum Field: Hashable { case new, confirm }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    headerView
                    passwordCreationForm
                        .padding(12)
                        .background(theme.tileBackground)
                        .cornerRadius(10)
                    
                    twoFactorToggle
                    securityTipsView
                        .padding(12)
                        .background(theme.tileBackground)
                        .cornerRadius(10)
                    
                    // REMOVED: backendSelectionView
                    
                    if let error = errorMessage {
                        errorView(error)
                    }
                    
                    actionButtons
                }
                .padding(32)
                .frame(maxWidth: 480)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.backgroundColor.ignoresSafeArea())
        }
        .tint(theme.badgeBackground)
        .sheet(isPresented: $show2FASetup) {
            if let passwordData = createdPasswordData {
                TwoFactorSetupAfterPasswordView(
                    masterPassword: passwordData,
                    onComplete: {
                        show2FASetup = false
                        completeSetup()
                    },
                    onSkip: {
                        show2FASetup = false
                        completeSetup()
                    }
                )
            }
        }
        .onAppear {
            setupInitialState()
            generateSecurityTips()
        }
        .onChange(of: newPasswordInput) { _ in
            updatePasswordStrength()
        }
        // REMOVED: showLocalWarning alert
        .alert("Weak Password", isPresented: $showWeakPasswordAlert) {
            Button("Use Anyway", role: .destructive) {
                proceedWithPasswordCreation()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your password is considered weak. Using a weak password may put your data at risk. Do you still want to use it?")
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: savePassword) {
                HStack {
                    if isCreatingPassword {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Image(systemName: "checkmark.shield")
                    }
                    Text(isCreatingPassword ? "Creating..." : "Create Password")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(isCreatingPassword || !canCreatePassword)
            .keyboardShortcut(.defaultAction)
            
            Text("Make sure to remember this password - it cannot be recovered if lost!")
                .font(.caption2)
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .foregroundStyle(theme.badgeBackground.gradient)
                .symbolEffect(.pulse)
            
            VStack(spacing: 4) {
                Text("Create Master Password")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(theme.primaryTextColor)
                
                Text("This password will protect all your data")
                    .font(.subheadline)
                    .foregroundColor(theme.secondaryTextColor)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    // MARK: - Password Creation Form
    private var passwordCreationForm: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                enhancedPasswordField("New Password", text: $newPasswordInput, field: .new)
                
                if !newPasswordInput.isEmpty {
                    passwordStrengthIndicator
                }
            }
            
            enhancedPasswordField("Confirm Password", text: $confirmPasswordInput, field: .confirm)
            
            HStack {
                Button(action: { showPassword.toggle() }) {
                    HStack {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                        Text(showPassword ? "Hide Password" : "Show Password")
                    }
                    .foregroundColor(theme.primaryTextColor)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Spacer()
            }
        }
    }
    
    // MARK: - Two-Factor Toggle
    private var twoFactorToggle: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $enable2FA) {
                HStack(spacing: 8) {
                    Image(systemName: "shield.checkered")
                        .foregroundColor(theme.badgeBackground)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Two-Factor Authentication")
                            .font(.headline)
                            .foregroundColor(theme.primaryTextColor)
                        Text("Add an extra layer of security with TOTP codes")
                            .font(.caption)
                            .foregroundColor(theme.secondaryTextColor)
                    }
                }
            }
            .toggleStyle(.switch)
            .padding(12)
            .background(theme.selectionFill)
            .cornerRadius(10)
            
            if enable2FA {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(theme.badgeBackground)
                    Text("You'll set up 2FA after creating your password")
                        .font(.caption)
                        .foregroundColor(theme.secondaryTextColor)
                }
                .padding(.horizontal, 12)
            }
        }
    }
    
    // MARK: - Password Strength Indicator
    private var passwordStrengthIndicator: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Strength:")
                    .font(.caption)
                    .foregroundColor(theme.secondaryTextColor)
                
                Text(strengthText)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(strengthColor)
                
                Spacer()
                
                Text("\(Int(passwordStrength * 100))%")
                    .font(.caption)
                    .foregroundColor(theme.secondaryTextColor)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.secondaryTextColor.opacity(0.2))
                        .frame(height: 4)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(strengthColor.gradient)
                        .frame(width: geometry.size.width * passwordStrength, height: 4)
                        .animation(.easeInOut(duration: 0.3), value: passwordStrength)
                }
            }
            .frame(height: 4)
        }
    }
    
    // MARK: - Security Tips View
    private var securityTipsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "lightbulb")
                    .foregroundColor(theme.badgeBackground)
                Text("Security Tips")
                    .font(.headline)
                    .foregroundColor(theme.primaryTextColor)
            }
            
            ForEach(securityTips, id: \.self) { tip in
                HStack(alignment: .top) {
                    Text("•")
                        .foregroundColor(theme.secondaryTextColor)
                    Text(tip)
                        .font(.caption)
                        .foregroundColor(theme.secondaryTextColor)
                    Spacer()
                }
            }
        }
    }
    
    // REMOVED: backendSelectionView entirely
    
    // MARK: - Error View
    private func errorView(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.red)
            Text(error)
                .foregroundColor(.red)
                .multilineTextAlignment(.leading)
        }
        .padding(12)
        .background(.red.opacity(0.1))
        .cornerRadius(8)
        .transition(.opacity.combined(with: .scale))
    }
    
    // MARK: - Enhanced Password Field
    @ViewBuilder
    private func enhancedPasswordField(_ placeholder: String, text: Binding<String>, field: Field) -> some View {
        ZStack(alignment: .trailing) {
            Group {
                if showPassword {
                    TextField(placeholder, text: text)
                        .foregroundColor(theme.primaryTextColor)
                } else {
                    SecureField(placeholder, text: text)
                        .foregroundColor(theme.primaryTextColor)
                }
            }
            .textFieldStyle(.roundedBorder)
            .focused($focusedField, equals: field)
            .font(.system(.body, design: .monospaced))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(focusedField == field ? theme.badgeBackground : .clear, lineWidth: 2)
            )
        }
    }
    
    // MARK: - Computed Properties
    
    // REMOVED: backendBinding
    // REMOVED: backendDescription
    // REMOVED: localStorageWarningMessage
    
    private var canCreatePassword: Bool {
        !newPasswordInput.isEmpty &&
        newPasswordInput == confirmPasswordInput
    }
    
    // MARK: - Setup and Logic Methods
    
    private func setupInitialState() {
        focusedField = .new
        // REMOVED: backend selection initialization
    }
    
    private func generateSecurityTips() {
        securityTips = [
            "Use at least 12 characters with mixed case, numbers, and symbols",
            "Avoid common words, personal information, or keyboard patterns",
            "Consider using a memorable passphrase with random words",
            "This password cannot be recovered if forgotten - write it down securely",
            "Enable biometric unlock after setup for convenience"
        ]
    }
    
    private func updatePasswordStrength() {
        let password = newPasswordInput
        guard !password.isEmpty else {
            passwordStrength = 0.0
            strengthColor = .red
            strengthText = "Very Weak"
            return
        }
        
        var score = 0.0
        
        if password.count >= 8 { score += 1 }
        if password.count >= 12 { score += 1 }
        if password.count >= 16 { score += 1 }
        
        if password.rangeOfCharacter(from: .uppercaseLetters) != nil { score += 1 }
        if password.rangeOfCharacter(from: .lowercaseLetters) != nil { score += 1 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil { score += 1 }
        if password.rangeOfCharacter(from: CharacterSet.punctuationCharacters.union(.symbols)) != nil { score += 1 }
        
        if isCommonPassword(password) { score -= 2 }
        if hasRepeatingPatterns(password) { score -= 1 }
        
        passwordStrength = max(0, min(score / 7.0, 1.0))
        
        updateStrengthDisplay()
    }
    
    private func updateStrengthDisplay() {
        switch passwordStrength {
        case 0..<0.3:
            strengthColor = .red
            strengthText = "Very Weak"
        case 0.3..<0.5:
            strengthColor = .orange
            strengthText = "Weak"
        case 0.5..<0.7:
            strengthColor = .yellow
            strengthText = "Fair"
        case 0.7..<0.9:
            strengthColor = .green
            strengthText = "Good"
        default:
            strengthColor = .green
            strengthText = "Strong"
        }
    }
    
    private func isCommonPassword(_ password: String) -> Bool {
        let commonPasswords = [
            "password", "123456", "password123", "admin", "qwerty",
            "letmein", "welcome", "monkey", "1234567890", "abc123"
        ]
        return commonPasswords.contains(password.lowercased())
    }
    
    private func hasRepeatingPatterns(_ password: String) -> Bool {
        if password.count >= 3 {
            let chars = Array(password)
            for i in 0..<(chars.count - 2) {
                if chars[i] == chars[i+1] && chars[i+1] == chars[i+2] {
                    return true
                }
            }
        }
        return false
    }
    
    // REMOVED: confirmLocalStorage()
    // REMOVED: cancelLocalStorage()
    
    private func savePassword() {
        CryptoHelper.wipeAllData(context: viewContext)
        
        guard !newPasswordInput.isEmpty else {
            showError("Password cannot be empty")
            return
        }
        
        guard newPasswordInput == confirmPasswordInput else {
            showError("Passwords do not match")
            return
        }
        
        if passwordStrength < 0.6 {
            showWeakPasswordAlert = true
            return
        }
        
        proceedWithPasswordCreation()
    }
    
    private func proceedWithPasswordCreation() {
        isCreatingPassword = true
        errorMessage = nil
        
        Task { @MainActor in
            // Small anti-timing + UX delay
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            
            await performPasswordCreation()
        }
    }

    @MainActor
    private func performPasswordCreation() async {
        print("[CreateMasterPasswordView] Creating master password...")
        
        // REMOVED: Backend selection code
        // storedBackend = selectedBackend.rawValue
        // CryptoHelper.setStorageBackendWithoutMigration(selectedBackend, context: viewContext)
        
        // Local storage is now the only option, so we just initialize it
        CryptoHelper.initializeLocalBackend()
        
        // 2. Convert password
        let passwordData = Data(newPasswordInput.utf8)
        var passwordCopy = passwordData
        defer { passwordCopy.secureWipe() }
        
        // 3. Set master password (async)
        await CryptoHelper.setMasterPassword(passwordData)
        print("[CreateMasterPasswordView] Master password set in local vault")
        
        // 4. Biometric storage — now fully async!
        if BiometricManager.shared.isBiometricAvailable {
            print("[CreateMasterPasswordView] Storing in biometric...")
            
            BiometricManager.shared.storeMasterPasswordSecure(passwordData)
            
            // Wait a moment for file write to complete (fire-and-forget is safe, but we can await status)
            try? await Task.sleep(nanoseconds: 300_000_000)
            
            if BiometricManager.shared.isPasswordStored {
                CryptoHelper.enableBiometricUnlock()
                print("[CreateMasterPasswordView] Biometric unlock enabled")
            }
        } else {
            print("[CreateMasterPasswordView] Biometric not available")
        }
        
        // 5. Save for 2FA setup
        createdPasswordData = passwordData // will be wiped in view's onDisappear or later
        
        // 6. Finalize
        withAnimation {
            passwordCreated = true
            isCreatingPassword = false
        }
        
        // 7. Show 2FA or complete
        if enable2FA {
            show2FASetup = true
        } else {
            completeSetup()
        }
        
        // 8. Clear UI
        clearSensitiveInputs()
    }
    
    private func completeSetup() {
        guard let passwordData = createdPasswordData else { return }
        
        defer {
            createdPasswordData?.secureWipe()
            createdPasswordData = nil
        }
        
        onComplete(passwordData)
    }
    
    private func clearSensitiveInputs() {
        newPasswordInput = ""
        confirmPasswordInput = ""
        passwordStrength = 0.0
        
        NSPasteboard.general.clearContents()
    }
    
    private func showError(_ message: String) {
        withAnimation(.easeInOut(duration: 0.3)) {
            errorMessage = message
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if errorMessage == message {
                withAnimation(.easeInOut(duration: 0.3)) {
                    errorMessage = nil
                }
            }
        }
    }
}


/*import SwiftUI
import CryptoKit

// MARK: - 2FA Setup After Password View

@available(macOS 15.0, *)
struct TwoFactorSetupAfterPasswordView: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.dismiss) private var dismiss
    
    let masterPassword: Data
    let onComplete: () -> Void
    let onSkip: () -> Void
    
    @State private var setupComplete = false
    
    var body: some View {
        ZStack {
            theme.backgroundColor.ignoresSafeArea()
            
            VStack(spacing: 20) {
                if setupComplete {
                    completionView
                } else {
                    TwoFactorSetupView(onSetupComplete: {
                        setupComplete = true
                    })
                    .environmentObject(theme)
                }
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { onSkip() }
                        .foregroundColor(theme.primaryTextColor)
                }
            }
        }
    }
    
    private var completionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(theme.badgeBackground)
            
            Text("Setup Complete!")
                .font(.title.bold())
                .foregroundColor(theme.primaryTextColor)
            
            Text("Your password manager is now secured with 2FA")
                .font(.subheadline)
                .foregroundColor(theme.secondaryTextColor)
            
            Button("Continue") { onComplete() }
                .buttonStyle(.borderedProminent)
                .tint(theme.badgeBackground)
                .controlSize(.large)
        }
        .padding(40)
        .background(theme.tileBackground)
        .cornerRadius(16)
        .shadow(radius: 10)
    }
}

// MARK: - Create Master Password View

import SwiftUI
import CryptoKit

// MARK: - Create Master Password View

@available(macOS 15.0, *)
struct CreateMasterPasswordView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var theme: ThemeManager
    @State private var newPasswordInput = ""
    @State private var confirmPasswordInput = ""
    @State private var showPassword = false
    @State private var errorMessage: String?
    @State private var passwordStrength: Double = 0.0
    @State private var strengthColor: Color = .red
    @State private var strengthText: String = "Very Weak"
    @State private var isCreatingPassword = false
    @State private var showWeakPasswordAlert = false
    
    // Security options
    @State private var enableDeviceBinding = true
    @State private var enable2FA = false
    
    // 2FA setup states
    @State private var show2FASetup = false
    @State private var passwordCreated = false
    @State private var createdPasswordData: Data?
    
    @FocusState private var focusedField: Field?
    
    @State private var securityTips: [String] = []
    
    var onComplete: (Data) -> Void
    
    enum Field: Hashable { case new, confirm }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    headerView
                    passwordCreationForm
                        .padding(12)
                        .background(theme.tileBackground)
                        .cornerRadius(10)
                    
                    securityTogglesView
                    securityTipsView
                        .padding(12)
                        .background(theme.tileBackground)
                        .cornerRadius(10)
                    
                    if let error = errorMessage {
                        errorView(error)
                    }
                    
                    actionButtons
                }
                .padding(32)
                .frame(maxWidth: 480)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.backgroundColor.ignoresSafeArea())
        }
        .tint(theme.badgeBackground)
        .sheet(isPresented: $show2FASetup) {
            if let passwordData = createdPasswordData {
                TwoFactorSetupAfterPasswordView(
                    masterPassword: passwordData,
                    onComplete: {
                        show2FASetup = false
                        completeSetup()
                    },
                    onSkip: {
                        show2FASetup = false
                        completeSetup()
                    }
                )
            }
        }
        .onAppear {
            setupInitialState()
            generateSecurityTips()
        }
        .onChange(of: newPasswordInput) { _ in
            updatePasswordStrength()
        }
        .onChange(of: enableDeviceBinding) { _ in
            generateSecurityTips()
        }
        .alert("Weak Password", isPresented: $showWeakPasswordAlert) {
            Button("Use Anyway", role: .destructive) {
                proceedWithPasswordCreation()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your password is considered weak. Using a weak password may put your data at risk. Do you still want to use it?")
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: savePassword) {
                HStack {
                    if isCreatingPassword {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Image(systemName: "checkmark.shield")
                    }
                    Text(isCreatingPassword ? "Creating..." : "Create Password")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(isCreatingPassword || !canCreatePassword)
            .keyboardShortcut(.defaultAction)
            
            Text("Make sure to remember this password - it cannot be recovered if lost!")
                .font(.caption2)
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .foregroundStyle(theme.badgeBackground.gradient)
                .symbolEffect(.pulse)
            
            VStack(spacing: 4) {
                Text("Create Master Password")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(theme.primaryTextColor)
                
                Text("This password will protect all your data")
                    .font(.subheadline)
                    .foregroundColor(theme.secondaryTextColor)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    // MARK: - Password Creation Form
    private var passwordCreationForm: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                enhancedPasswordField("New Password", text: $newPasswordInput, field: .new)
                
                if !newPasswordInput.isEmpty {
                    passwordStrengthIndicator
                }
            }
            
            enhancedPasswordField("Confirm Password", text: $confirmPasswordInput, field: .confirm)
            
            HStack {
                Button(action: { showPassword.toggle() }) {
                    HStack {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                        Text(showPassword ? "Hide Password" : "Show Password")
                    }
                    .foregroundColor(theme.primaryTextColor)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Spacer()
            }
        }
    }
    
    // MARK: - Security Toggles
    private var securityTogglesView: some View {
        VStack(spacing: 16) {
            // Device Binding Toggle
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $enableDeviceBinding) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield")
                            .foregroundColor(theme.badgeBackground)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable Device Binding")
                                .font(.headline)
                                .foregroundColor(theme.primaryTextColor)
                            Text("Bind encrypted data to this specific device")
                                .font(.caption)
                                .foregroundColor(theme.secondaryTextColor)
                        }
                    }
                }
                .toggleStyle(.switch)
                .padding(12)
                .background(theme.selectionFill)
                .cornerRadius(10)
                
                if enableDeviceBinding {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(theme.badgeBackground)
                        Text("Higher security: Passwords won't work if moved to another device")
                            .font(.caption)
                            .foregroundColor(theme.secondaryTextColor)
                    }
                    .padding(.horizontal, 12)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Lower security: Data can be moved between devices")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 12)
                }
            }
            
            // Two-Factor Toggle
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $enable2FA) {
                    HStack(spacing: 8) {
                        Image(systemName: "shield.checkered")
                            .foregroundColor(theme.badgeBackground)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable Two-Factor Authentication")
                                .font(.headline)
                                .foregroundColor(theme.primaryTextColor)
                            Text("Add an extra layer of security with TOTP codes")
                                .font(.caption)
                                .foregroundColor(theme.secondaryTextColor)
                        }
                    }
                }
                .toggleStyle(.switch)
                .padding(12)
                .background(theme.selectionFill)
                .cornerRadius(10)
                
                if enable2FA {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(theme.badgeBackground)
                        Text("You'll set up 2FA after creating your password")
                            .font(.caption)
                            .foregroundColor(theme.secondaryTextColor)
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
    }
    
    // MARK: - Password Strength Indicator
    private var passwordStrengthIndicator: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Strength:")
                    .font(.caption)
                    .foregroundColor(theme.secondaryTextColor)
                
                Text(strengthText)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(strengthColor)
                
                Spacer()
                
                Text("\(Int(passwordStrength * 100))%")
                    .font(.caption)
                    .foregroundColor(theme.secondaryTextColor)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.secondaryTextColor.opacity(0.2))
                        .frame(height: 4)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(strengthColor.gradient)
                        .frame(width: geometry.size.width * passwordStrength, height: 4)
                        .animation(.easeInOut(duration: 0.3), value: passwordStrength)
                }
            }
            .frame(height: 4)
        }
    }
    
    // MARK: - Security Tips View
    private var securityTipsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "lightbulb")
                    .foregroundColor(theme.badgeBackground)
                Text("Security Tips")
                    .font(.headline)
                    .foregroundColor(theme.primaryTextColor)
            }
            
            ForEach(securityTips, id: \.self) { tip in
                HStack(alignment: .top) {
                    Text("•")
                        .foregroundColor(theme.secondaryTextColor)
                    Text(tip)
                        .font(.caption)
                        .foregroundColor(theme.secondaryTextColor)
                    Spacer()
                }
            }
        }
    }
    
    // MARK: - Error View
    private func errorView(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.red)
            Text(error)
                .foregroundColor(.red)
                .multilineTextAlignment(.leading)
        }
        .padding(12)
        .background(.red.opacity(0.1))
        .cornerRadius(8)
        .transition(.opacity.combined(with: .scale))
    }
    
    // MARK: - Enhanced Password Field
    @ViewBuilder
    private func enhancedPasswordField(_ placeholder: String, text: Binding<String>, field: Field) -> some View {
        ZStack(alignment: .trailing) {
            Group {
                if showPassword {
                    TextField(placeholder, text: text)
                        .foregroundColor(theme.primaryTextColor)
                } else {
                    SecureField(placeholder, text: text)
                        .foregroundColor(theme.primaryTextColor)
                }
            }
            .textFieldStyle(.roundedBorder)
            .focused($focusedField, equals: field)
            .font(.system(.body, design: .monospaced))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(focusedField == field ? theme.badgeBackground : .clear, lineWidth: 2)
            )
        }
    }
    
    // MARK: - Computed Properties
    
    private var canCreatePassword: Bool {
        !newPasswordInput.isEmpty &&
        newPasswordInput == confirmPasswordInput
    }
    
    // MARK: - Setup and Logic Methods
    
    private func setupInitialState() {
        focusedField = .new
    }
    
    private func generateSecurityTips() {
        securityTips = [
            "Use at least 12 characters with mixed case, numbers, and symbols",
            "Avoid common words, personal information, or keyboard patterns",
            "Consider using a memorable passphrase with random words",
            "This password cannot be recovered if forgotten - write it down securely",
            enableDeviceBinding
                ? "Device binding adds extra security but limits portability"
                : "Device binding disabled allows moving data between devices",
            "Enable biometric unlock after setup for convenience"
        ]
    }
    
    private func updatePasswordStrength() {
        let password = newPasswordInput
        guard !password.isEmpty else {
            passwordStrength = 0.0
            strengthColor = .red
            strengthText = "Very Weak"
            return
        }
        
        var score = 0.0
        
        if password.count >= 8 { score += 1 }
        if password.count >= 12 { score += 1 }
        if password.count >= 16 { score += 1 }
        
        if password.rangeOfCharacter(from: .uppercaseLetters) != nil { score += 1 }
        if password.rangeOfCharacter(from: .lowercaseLetters) != nil { score += 1 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil { score += 1 }
        if password.rangeOfCharacter(from: CharacterSet.punctuationCharacters.union(.symbols)) != nil { score += 1 }
        
        if isCommonPassword(password) { score -= 2 }
        if hasRepeatingPatterns(password) { score -= 1 }
        
        passwordStrength = max(0, min(score / 7.0, 1.0))
        
        updateStrengthDisplay()
    }
    
    private func updateStrengthDisplay() {
        switch passwordStrength {
        case 0..<0.3:
            strengthColor = .red
            strengthText = "Very Weak"
        case 0.3..<0.5:
            strengthColor = .orange
            strengthText = "Weak"
        case 0.5..<0.7:
            strengthColor = .yellow
            strengthText = "Fair"
        case 0.7..<0.9:
            strengthColor = .green
            strengthText = "Good"
        default:
            strengthColor = .green
            strengthText = "Strong"
        }
    }
    
    private func isCommonPassword(_ password: String) -> Bool {
        let commonPasswords = [
            "password", "123456", "password123", "admin", "qwerty",
            "letmein", "welcome", "monkey", "1234567890", "abc123"
        ]
        return commonPasswords.contains(password.lowercased())
    }
    
    private func hasRepeatingPatterns(_ password: String) -> Bool {
        if password.count >= 3 {
            let chars = Array(password)
            for i in 0..<(chars.count - 2) {
                if chars[i] == chars[i+1] && chars[i+1] == chars[i+2] {
                    return true
                }
            }
        }
        return false
    }
    
    private func savePassword() {
        CryptoHelper.wipeAllData(context: viewContext)
        
        guard !newPasswordInput.isEmpty else {
            showError("Password cannot be empty")
            return
        }
        
        guard newPasswordInput == confirmPasswordInput else {
            showError("Passwords do not match")
            return
        }
        
        if passwordStrength < 0.6 {
            showWeakPasswordAlert = true
            return
        }
        
        proceedWithPasswordCreation()
    }
    
    private func proceedWithPasswordCreation() {
        isCreatingPassword = true
        errorMessage = nil
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            await performPasswordCreation()
        }
    }

    @MainActor
    private func performPasswordCreation() async {
        print("[CreateMasterPasswordView] Creating master password...")
        
        // Initialize local backend
        CryptoHelper.initializeLocalBackend()
        
        // Convert password
        let passwordData = Data(newPasswordInput.utf8)
        var passwordCopy = passwordData
        defer { passwordCopy.secureWipe() }
        
        // Set master password (async)
        await CryptoHelper.setMasterPassword(passwordData)
        print("[CreateMasterPasswordView] Master password set in local vault")
        
        // IMPORTANT: Save device binding preference AFTER master password is set
        // This is because settings are encrypted with the master key
        let deviceBindingSaved = CryptoHelper.saveSetting(enableDeviceBinding, key: .deviceBindingEnabled)
        if deviceBindingSaved {
            print("[CreateMasterPasswordView] Device binding: \(enableDeviceBinding ? "enabled" : "disabled")")
        } else {
            print("[CreateMasterPasswordView] ⚠️ Failed to save device binding preference")
        }
        
        // Biometric storage
        if BiometricManager.shared.isBiometricAvailable {
            print("[CreateMasterPasswordView] Storing in biometric...")
            
            BiometricManager.shared.storeMasterPasswordSecure(passwordData)
            
            try? await Task.sleep(nanoseconds: 300_000_000)
            
            if BiometricManager.shared.isPasswordStored {
                CryptoHelper.enableBiometricUnlock()
                print("[CreateMasterPasswordView] Biometric unlock enabled")
            }
        } else {
            print("[CreateMasterPasswordView] Biometric not available")
        }
        
        // Save for 2FA setup
        createdPasswordData = passwordData
        
        // Finalize
        withAnimation {
            passwordCreated = true
            isCreatingPassword = false
        }
        
        // Show 2FA or complete
        if enable2FA {
            show2FASetup = true
        } else {
            completeSetup()
        }
        
        // Clear UI
        clearSensitiveInputs()
    }
    
    private func completeSetup() {
        guard let passwordData = createdPasswordData else { return }
        
        defer {
            createdPasswordData?.secureWipe()
            createdPasswordData = nil
        }
        
        onComplete(passwordData)
    }
    
    private func clearSensitiveInputs() {
        newPasswordInput = ""
        confirmPasswordInput = ""
        passwordStrength = 0.0
        
        NSPasteboard.general.clearContents()
    }
    
    private func showError(_ message: String) {
        withAnimation(.easeInOut(duration: 0.3)) {
            errorMessage = message
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if errorMessage == message {
                withAnimation(.easeInOut(duration: 0.3)) {
                    errorMessage = nil
                }
            }
        }
    }
}

*/
