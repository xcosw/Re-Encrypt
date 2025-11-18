import SwiftUI
import CryptoKit

// MARK: - 2FA Setup After Password View

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
    @AppStorage("CryptoHelper.StorageBackend") private var storedBackend: String = StorageBackend.keychain.rawValue
    @State private var selectedBackend: StorageBackend = .keychain
    
    // Security warnings
    @State private var showLocalWarning = false
    @State private var pendingBackend: StorageBackend?
    @State private var lastBackend: StorageBackend = .keychain
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
                    
                    backendSelectionView
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
        .alert("Warning: Device-Bound Storage", isPresented: $showLocalWarning, presenting: pendingBackend) { backend in
            Button("I Understand", role: .destructive) {
                confirmLocalStorage()
            }
            Button("Cancel", role: .cancel) {
                cancelLocalStorage()
            }
        } message: { _ in
            Text(localStorageWarningMessage)
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
    
    // MARK: - Backend Selection View
    private var backendSelectionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Storage Backend")
                .font(.headline)
                .foregroundColor(theme.primaryTextColor)
            
            Picker("Storage Backend", selection: backendBinding) {
                Label {
                    VStack(alignment: .leading) {
                        Text("Keychain")
                            .foregroundColor(theme.primaryTextColor)
                        Text("System keychain (recommended)")
                            .font(.caption2)
                            .foregroundColor(theme.secondaryTextColor)
                    }
                } icon: {
                    Image(systemName: "lock.shield")
                        .foregroundColor(theme.badgeBackground)
                }
                .tag(StorageBackend.keychain)
                
                Label {
                    VStack(alignment: .leading) {
                        Text("Local Files")
                            .foregroundColor(theme.primaryTextColor)
                        Text("Device-bound encryption")
                            .font(.caption2)
                            .foregroundColor(theme.secondaryTextColor)
                    }
                } icon: {
                    Image(systemName: "folder.badge.gearshape")
                        .foregroundColor(theme.badgeBackground)
                }
                .tag(StorageBackend.local)
            }
            .pickerStyle(.segmented)
            
            Text(backendDescription)
                .font(.caption)
                .foregroundColor(theme.secondaryTextColor)
                .padding(.top, 4)
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
    
    private var backendBinding: Binding<StorageBackend> {
        Binding(
            get: { selectedBackend },
            set: { newValue in
                if newValue == .local && selectedBackend != .local {
                    pendingBackend = newValue
                    showLocalWarning = true
                } else {
                    lastBackend = selectedBackend
                    selectedBackend = newValue
                }
            }
        )
    }
    
    private var backendDescription: String {
        switch selectedBackend {
        case .keychain:
            return "Uses the system keychain for maximum security and compatibility across app updates."
        case .local:
            return "Creates device-bound encrypted files. Data cannot be recovered if device is lost or replaced."
        }
    }
    
    private var canCreatePassword: Bool {
        !newPasswordInput.isEmpty &&
        newPasswordInput == confirmPasswordInput
    }
    
    private var localStorageWarningMessage: String {
        """
        If you choose Local storage, your secrets are cryptographically bound to this device's hardware.
        
        • If your device is lost, replaced, or has major hardware changes, your secrets will become unrecoverable
        • Copying the app files to another computer will NOT allow recovery or decryption
        • For maximum portability, use Keychain storage
        
        Are you sure you want to use device-bound Local storage?
        """
    }
    
    // MARK: - Setup and Logic Methods
    
    private func setupInitialState() {
        focusedField = .new
        selectedBackend = StorageBackend(rawValue: storedBackend) ?? .keychain
        lastBackend = selectedBackend
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
    
    private func confirmLocalStorage() {
        lastBackend = .local
        selectedBackend = .local
        showLocalWarning = false
        pendingBackend = nil
    }
    
    private func cancelLocalStorage() {
        selectedBackend = lastBackend
        showLocalWarning = false
        pendingBackend = nil
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
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            performPasswordCreation()
        }
    }
    
    private func performPasswordCreation() {
        print("[CreateMasterPasswordView] Creating password...")
        
        storedBackend = selectedBackend.rawValue
        CryptoHelper.setStorageBackendWithoutMigration(selectedBackend, context: viewContext)
        
        let passwordData = Data(newPasswordInput.utf8)
        
        // Set master password - this will now setup the custom keychain with the master password
        CryptoHelper.setMasterPassword(passwordData)
        print("[CreateMasterPasswordView] CryptoHelper password set")
        
        // Store with biometric if available
        if BiometricManager.shared.isBiometricAvailable {
            print("[CreateMasterPasswordView] Storing with biometric...")
            BiometricManager.shared.storeMasterPassword(passwordData)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                print("[CreateMasterPasswordView] Storage complete: \(BiometricManager.shared.isPasswordStored)")
                if BiometricManager.shared.isPasswordStored {
                    CryptoHelper.enableBiometricUnlock()
                }
            }
        } else {
            print("[CreateMasterPasswordView] Biometric not available")
        }
        
        // Store password for 2FA setup
        createdPasswordData = passwordData
        passwordCreated = true
        isCreatingPassword = false
        
        // Show 2FA setup if enabled
        if enable2FA {
            show2FASetup = true
        } else {
            completeSetup()
        }
        
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
