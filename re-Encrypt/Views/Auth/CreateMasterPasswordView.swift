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

import SwiftUI
import CryptoKit

// MARK: - Recovery Codes Display View

@available(macOS 15.0, *)
struct RecoveryCodesView: View {
    @EnvironmentObject private var theme: ThemeManager
    let recoveryCodes: [String]
    let onComplete: () -> Void
    
    @State private var isConfirmed = false
    @State private var isCopied = false
    
    var body: some View {
        ZStack {
            theme.backgroundColor.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    headerView
                    
                    warningView
                    
                    codesGridView
                    
                    actionButtons
                }
                .padding(32)
                .frame(maxWidth: 600)
            }
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .foregroundStyle(theme.badgeBackground.gradient)
                .symbolEffect(.pulse)
            
            VStack(spacing: 4) {
                Text("Recovery Codes")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(theme.primaryTextColor)
                
                Text("Save these codes in a secure location")
                    .font(.subheadline)
                    .foregroundColor(theme.secondaryTextColor)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    private var warningView: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("IMPORTANT")
                    .font(.headline)
                    .foregroundColor(.orange)
                
                Text("Each code can only be used once. Store them securely - they cannot be recovered if lost.")
                    .font(.caption)
                    .foregroundColor(theme.secondaryTextColor)
            }
            
            Spacer()
        }
        .padding(16)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var codesGridView: some View {
        VStack(spacing: 16) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Array(recoveryCodes.enumerated()), id: \.offset) { index, code in
                    HStack {
                        Text("\(index + 1).")
                            .font(.caption)
                            .foregroundColor(theme.secondaryTextColor)
                            .frame(width: 30, alignment: .leading)
                        
                        Text(code)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(theme.primaryTextColor)
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(theme.tileBackground)
                            .cornerRadius(6)
                    }
                }
            }
            
            Button(action: copyAllCodes) {
                HStack(spacing: 8) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    Text(isCopied ? "Copied!" : "Copy All Codes")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(isCopied ? .green : theme.badgeBackground)
        }
        .padding(16)
        .background(theme.selectionFill)
        .cornerRadius(12)
    }
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Toggle(isOn: $isConfirmed) {
                HStack {
                    Image(systemName: "checkmark.shield")
                        .foregroundColor(theme.badgeBackground)
                    Text("I have saved these recovery codes securely")
                        .font(.subheadline)
                        .foregroundColor(theme.primaryTextColor)
                }
            }
            .toggleStyle(.switch)
            .padding(12)
            .background(theme.tileBackground)
            .cornerRadius(10)
            
            Button(action: onComplete) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Continue")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isConfirmed)
            
            Text("⚠️ Without these codes, you cannot recover your account if you forget your password")
                .font(.caption2)
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
        }
    }
    
    private func copyAllCodes() {
        let codesText = recoveryCodes.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(codesText, forType: .string)
        
        isCopied = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCopied = false
        }
    }
}

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
    @State private var isCreatingPassword = false
    @State private var showWeakPasswordAlert = false
    
    // Recovery codes states
    @State private var showRecoveryCodes = false
    @State private var generatedRecoveryCodes: [String] = []
    
    // 2FA setup states
    @State private var show2FASetup = false
    @State private var enable2FA = false
    @State private var enableRecoveryCodes = true
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
                    
                    securityOptionsView
                    
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
        .sheet(isPresented: $showRecoveryCodes) {
            RecoveryCodesView(
                recoveryCodes: generatedRecoveryCodes,
                onComplete: {
                    showRecoveryCodes = false
                    if enable2FA {
                        show2FASetup = true
                    } else {
                        completeSetup()
                    }
                }
            )
            .environmentObject(theme)
        }
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
                    passwordRequirementsView
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
    
    // MARK: - Password Requirements View
    private var passwordRequirementsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Requirements:")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(theme.secondaryTextColor)
            
            let validation = getPasswordValidation()
            
            requirementItem("At least 12 characters", met: validation.lengthMet)
            
            requirementItem("At least 3 of the following:", met: validation.complexityMet)
            
            HStack(spacing: 12) {
                Spacer().frame(width: 16)
                VStack(alignment: .leading, spacing: 4) {
                    complexitySubItem("Uppercase letter (A-Z)", met: validation.hasUppercase)
                    complexitySubItem("Lowercase letter (a-z)", met: validation.hasLowercase)
                    complexitySubItem("Number (0-9)", met: validation.hasNumber)
                    complexitySubItem("Symbol (!@#$...)", met: validation.hasSpecial)
                }
            }
        }
        .padding(12)
        .background(theme.selectionFill)
        .cornerRadius(8)
    }
    
    private func requirementItem(_ text: String, met: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .foregroundColor(met ? .green : theme.secondaryTextColor.opacity(0.5))
                .font(.caption)
            Text(text)
                .font(.caption)
                .foregroundColor(met ? theme.primaryTextColor : theme.secondaryTextColor)
        }
    }
    
    private func complexitySubItem(_ text: String, met: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: met ? "checkmark" : "minus")
                .font(.system(size: 8))
                .foregroundColor(met ? .green : theme.secondaryTextColor.opacity(0.5))
            Text(text)
                .font(.caption2)
                .foregroundColor(met ? theme.primaryTextColor : theme.secondaryTextColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(met ? Color.green.opacity(0.1) : Color.clear)
        .cornerRadius(4)
    }
    
    // MARK: - Security Options View
    private var securityOptionsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Recovery Codes Toggle
            Toggle(isOn: $enableRecoveryCodes) {
                HStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .foregroundColor(theme.badgeBackground)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Generate Recovery Codes")
                            .font(.headline)
                            .foregroundColor(theme.primaryTextColor)
                        Text("Get 10 one-time codes to recover your account")
                            .font(.caption)
                            .foregroundColor(theme.secondaryTextColor)
                    }
                }
            }
            .toggleStyle(.switch)
            .padding(12)
            .background(theme.selectionFill)
            .cornerRadius(10)
            
            // Two-Factor Toggle
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
            
            if enableRecoveryCodes || enable2FA {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(theme.badgeBackground)
                    Text("You'll complete setup after creating your password")
                        .font(.caption)
                        .foregroundColor(theme.secondaryTextColor)
                }
                .padding(.horizontal, 12)
            }
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
    
    // MARK: - Password Validation
    
    private struct PasswordValidation {
        let lengthMet: Bool
        let hasUppercase: Bool
        let hasLowercase: Bool
        let hasNumber: Bool
        let hasSpecial: Bool
        let complexityMet: Bool
        let isValid: Bool
    }
    
    private func getPasswordValidation() -> PasswordValidation {
        let password = newPasswordInput
#if DEBUG
        let lengthMet = password.count >= 4
#else
        let lengthMet = password.count >= 12
#endif
        let hasUppercase = password.contains(where: { $0.isUppercase })
        let hasLowercase = password.contains(where: { $0.isLowercase })
        let hasNumber = password.contains(where: { $0.isNumber })
        let hasSpecial = password.contains(where: { !$0.isLetter && !$0.isNumber })
        
        let complexityCount = [hasUppercase, hasLowercase, hasNumber, hasSpecial].filter { $0 }.count
        let complexityMet = complexityCount >= 3
        
        let isValid = lengthMet && complexityMet
        
        return PasswordValidation(
            lengthMet: lengthMet,
            hasUppercase: hasUppercase,
            hasLowercase: hasLowercase,
            hasNumber: hasNumber,
            hasSpecial: hasSpecial,
            complexityMet: complexityMet,
            isValid: isValid
        )
    }
    
    // MARK: - Computed Properties
    
    private var canCreatePassword: Bool {
        let validation = getPasswordValidation()
        return !newPasswordInput.isEmpty &&
               newPasswordInput == confirmPasswordInput &&
               validation.isValid
    }
    
    // MARK: - Setup and Logic Methods
    
    private func setupInitialState() {
        focusedField = .new
    }
    
    private func generateSecurityTips() {
        securityTips = [
            "Avoid common words, personal information, or keyboard patterns",
            "Consider using a memorable passphrase with random words",
            "Enable recovery codes to regain access if you forget your password",
            "Enable biometric unlock after setup for convenience",
            "Never share your master password with anyone"
        ]
    }
    
    private func savePassword() {
        guard !newPasswordInput.isEmpty else {
            showError("Password cannot be empty")
            return
        }
        
        guard newPasswordInput == confirmPasswordInput else {
            showError("Passwords do not match")
            return
        }
        
        // Validate using CryptoHelper's validation
        let passwordData = Data(newPasswordInput.utf8)
        let validation = getPasswordValidation()
        
        if !validation.isValid {
            showError("Password does not meet security requirements")
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

        CryptoHelper.initializeLocalBackend()

        let passwordData = Data(newPasswordInput.utf8)
        var passwordCopy = passwordData
        defer { passwordCopy.secureWipe() }

        do {
            try await CryptoHelper.setMasterPassword(passwordData)
            print("[CreateMasterPasswordView] ✅ Master password set successfully")
        } catch {
            print("[CreateMasterPasswordView] ❌ Failed to set master password: \(error)")
            errorMessage = "Failed to create password: \(error.localizedDescription)"
            isCreatingPassword = false
            return
        }

        // Generate recovery codes if enabled
        if enableRecoveryCodes {
            do {
                generatedRecoveryCodes = try await CryptoHelper.setupRecoveryCodes(masterPassword: passwordData)
                print("[CreateMasterPasswordView] ✅ Recovery codes generated")
            } catch {
                print("[CreateMasterPasswordView] ⚠️ Failed to generate recovery codes: \(error)")
                // Non-fatal - continue without recovery codes
            }
        }

        // Biometric storage
        if BiometricManager.shared.isBiometricAvailable {
            print("[CreateMasterPasswordView] Storing in biometric...")
            BiometricManager.shared.storeMasterPasswordSecure(passwordData)
            try? await Task.sleep(nanoseconds: 300_000_000)
            
            if BiometricManager.shared.isPasswordStored {
                CryptoHelper.enableBiometricUnlock()
                print("[CreateMasterPasswordView] ✅ Biometric unlock enabled")
            }
        }

        createdPasswordData = passwordData
        passwordCreated = true
        isCreatingPassword = false

        // Show recovery codes first if enabled
        if enableRecoveryCodes && !generatedRecoveryCodes.isEmpty {
            showRecoveryCodes = true
        } else if enable2FA {
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
