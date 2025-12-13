import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - 2FA Setup View

@available(macOS 15.0, *)
struct TwoFactorSetupView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.dismiss) private var dismiss
    var onSetupComplete: (() -> Void)? = nil
    @State private var currentStep: SetupStep = .verify
    @State private var masterPassword = ""
    @State private var secret = ""
    @State private var qrCodeURL = ""
    @State private var backupCodes: [String] = []
    @State private var verificationCode = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showBackupCodes = false
    
    enum SetupStep {
        case verify
        case scan
        case verifyCode
        case backupCodes
        case complete
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            // Content
            ScrollView {
                VStack(spacing: 30) {
                    switch currentStep {
                    case .verify:
                        verifyPasswordStep
                    case .scan:
                        scanQRStep
                    case .verifyCode:
                        verifyCodeStep
                    case .backupCodes:
                        backupCodesStep
                    case .complete:
                        completeStep
                    }
                }
                .padding(30)
            }
            
            Divider()
            
            // Footer
            footer
        }
        .frame(width: 500, height: 600)
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(theme.badgeBackground.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(theme.badgeBackground.gradient)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Two-Factor Authentication")
                    .font(.headline)
                    .foregroundColor(theme.primaryTextColor)
                
                Text(stepDescription)
                    .font(.caption)
                    .foregroundColor(theme.secondaryTextColor)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    private var stepDescription: String {
        switch currentStep {
        case .verify: return "Verify your identity"
        case .scan: return "Scan QR code with authenticator app"
        case .verifyCode: return "Enter verification code"
        case .backupCodes: return "Save your backup codes"
        case .complete: return "Setup complete"
        }
    }
    
    // MARK: - Step 1: Verify Password
    
    private var verifyPasswordStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 60))
                .foregroundStyle(theme.badgeBackground.gradient)
                .padding(.bottom, 10)
            
            Text("Verify Your Master Password")
                .font(.title2.weight(.semibold))
                .foregroundColor(theme.primaryTextColor)
            
            Text("Enter your master password to continue setting up 2FA")
                .font(.subheadline)
                .foregroundColor(theme.secondaryTextColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            SecureField("Master Password", text: $masterPassword)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)
                .onSubmit {
                    Task { @MainActor in
                        await verifyPassword()
                    }
                }
        }
    }
    
    // MARK: - Step 2: Scan QR Code
    
    private var scanQRStep: some View {
        VStack(spacing: 20) {
            Text("Scan QR Code")
                .font(.title2.weight(.semibold))
                .foregroundColor(theme.primaryTextColor)
            
            Text("Use an authenticator app like Authenticator, Authy, or 1Password")
                .font(.subheadline)
                .foregroundColor(theme.secondaryTextColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            if let qrImage = generateQRCode(from: qrCodeURL) {
                Image(nsImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 250, height: 250)
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(radius: 3)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Can't scan? Enter this code manually:")
                    .font(.caption)
                    .foregroundColor(theme.secondaryTextColor)
                
                HStack {
                    Text(formatSecret(secret))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(theme.primaryTextColor)
                        .textSelection(.enabled)
                    
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(secret, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(theme.badgeBackground)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Step 3: Verify Code
    
    private var verifyCodeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "number.square.fill")
                .font(.system(size: 60))
                .foregroundStyle(theme.badgeBackground.gradient)
                .padding(.bottom, 10)
            
            Text("Enter Verification Code")
                .font(.title2.weight(.semibold))
                .foregroundColor(theme.primaryTextColor)
            
            Text("Enter the 6-digit code from your authenticator app")
                .font(.subheadline)
                .foregroundColor(theme.secondaryTextColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            TextField("000000", text: $verificationCode)
                .textFieldStyle(.roundedBorder)
                .font(.system(.title3, design: .monospaced))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 200)
                .onChange(of: verificationCode) { newValue in
                    // Only allow digits
                    verificationCode = newValue.filter { $0.isNumber }
                    // Limit to 6 digits
                    if verificationCode.count > 6 {
                        verificationCode = String(verificationCode.prefix(6))
                    }
                    // Auto-verify when 6 digits entered
                    if verificationCode.count == 6 {
                        Task {
                            await
                        verifyCodeAndContinue()
                    }}
                }
        }
    }
    
    // MARK: - Step 4: Backup Codes
    
    private var backupCodesStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 60))
                .foregroundStyle(theme.badgeBackground.gradient)
                .padding(.bottom, 10)
            
            Text("Save Your Backup Codes")
                .font(.title2.weight(.semibold))
                .foregroundColor(theme.primaryTextColor)
            
            Text("Keep these codes safe. Each can be used once if you lose access to your authenticator.")
                .font(.subheadline)
                .foregroundColor(theme.secondaryTextColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(backupCodes.enumerated()), id: \.offset) { index, code in
                    HStack {
                        Text("\(index + 1).")
                            .font(.caption)
                            .foregroundColor(theme.secondaryTextColor)
                            .frame(width: 30, alignment: .trailing)
                        
                        Text(code)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(theme.primaryTextColor)
                            .textSelection(.enabled)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)
            
            Button {
                copyAllCodes()
            } label: {
                Label("Copy All Codes", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
        }
    }
    
    // MARK: - Step 5: Complete
    
    private var completeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green.gradient)
                .padding(.bottom, 10)
            
            Text("2FA Enabled Successfully!")
                .font(.title.weight(.bold))
                .foregroundColor(theme.primaryTextColor)
            
            Text("Your account is now protected with two-factor authentication")
                .font(.subheadline)
                .foregroundColor(theme.secondaryTextColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 12) {
                Label("Backup codes saved securely", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                
                Label("TOTP configured successfully", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                
                Label("Master password verified", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
            .padding()
            .background(Color.green.opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Footer
    
    private var footer: some View {
            HStack(spacing: 12) {
                if currentStep != .complete {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
                
                Spacer()
                
                if currentStep == .verify {
                    Button("Continue") {
                        Task { @MainActor in
                            await verifyPassword()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.badgeBackground)
                    .disabled(masterPassword.isEmpty)
                } else if currentStep == .scan {
                    Button("Continue") {
                        currentStep = .verifyCode
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.badgeBackground)
                } else if currentStep == .verifyCode {
                    Button("Verify") {
                        Task {
                            await verifyCodeAndContinue()
                    }  }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.badgeBackground)
                    .disabled(verificationCode.count != 6)
                } else if currentStep == .backupCodes {
                    Button("Complete Setup") {
                        Task {
                            await
                        finalizeSetup()
                    } }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.badgeBackground)
                } else if currentStep == .complete {
                    Button("Done") {
                        // CALL THE CALLBACK HERE
                        
                        onSetupComplete?()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.badgeBackground)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        }
    
    // MARK: - Actions
    
    @MainActor
    private func verifyPassword() async {
        let passwordData = Data(masterPassword.utf8)
        var passwordCopy = passwordData
        defer {
            passwordCopy.secureWipe()
            masterPassword = ""
        }
        
        guard await CryptoHelper.verifyMasterPassword(password: passwordData, context: viewContext) else {
            errorMessage = "Incorrect master password"
            showError = true
            return
        }
        
        guard let setup = TwoFactorAuthManager.shared.setup() else {
            errorMessage = "Failed to generate 2FA secret"
            showError = true
            return
        }
        
        secret = setup.secret
        qrCodeURL = setup.qrCodeURL
        backupCodes = setup.backupCodes
        
        withAnimation {
            currentStep = .scan
        }
    }
    
    private func verifyCodeAndContinue() async {
        let passwordData = Data(masterPassword.utf8)
        
        guard await TwoFactorAuthManager.shared.verify(code: verificationCode, masterPassword: passwordData) else {
            errorMessage = "Invalid verification code. Please try again."
            showError = true
            verificationCode = ""
            return
        }
        
        currentStep = .backupCodes
    }
    
    private func finalizeSetup() async {
        let passwordData = Data(masterPassword.utf8)
        
        guard await TwoFactorAuthManager.shared.enable(
            secret: secret,
            backupCodes: backupCodes,
            masterPassword: passwordData
        ) else {
            errorMessage = "Failed to enable 2FA"
            showError = true
            return
        }
        
        currentStep = .complete
    }
    
    private func copyAllCodes() {
        let allCodes = backupCodes.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(allCodes, forType: .string)
    }
    
    // MARK: - Helpers
    
    private func formatSecret(_ secret: String) -> String {
        var formatted = ""
        for (index, char) in secret.enumerated() {
            if index > 0 && index % 4 == 0 {
                formatted += " "
            }
            formatted.append(char)
        }
        return formatted
    }
    
    private func generateQRCode(from string: String) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        
        guard let outputImage = filter.outputImage else { return nil }
        
        let scaleX: CGFloat = 250 / outputImage.extent.size.width
        let scaleY: CGFloat = 250 / outputImage.extent.size.height
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        
        let nsImage = NSImage(size: NSSize(width: 250, height: 250))
        nsImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(cgImage: cgImage, size: NSSize(width: 250, height: 250))
            .draw(at: .zero, from: NSRect(x: 0, y: 0, width: 250, height: 250), operation: .copy, fraction: 1.0)
        nsImage.unlockFocus()
        
        return nsImage
    }
}

// MARK: - 2FA Verification View (for login)

@available(macOS 15.0, *)
struct TwoFactorVerificationView: View {
    @EnvironmentObject private var theme: ThemeManager
    
    let masterPassword: Data
    let onSuccess: () -> Void
    let onCancel: () -> Void
    
    @State private var verificationCode = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var useBackupCode = false
    
    var body: some View {
        VStack(spacing: 30) {
            // Header
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(theme.badgeBackground.opacity(0.15))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(theme.badgeBackground.gradient)
                }
                
                Text("Two-Factor Authentication")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(theme.primaryTextColor)
                
                Text(useBackupCode ? "Enter one of your backup codes" : "Enter the 6-digit code from your authenticator app")
                    .font(.subheadline)
                    .foregroundColor(theme.secondaryTextColor)
                    .multilineTextAlignment(.center)
            }
            
            // Code input
            TextField(useBackupCode ? "Backup Code" : "000000", text: $verificationCode)
                .textFieldStyle(.roundedBorder)
                .font(.system(.title3, design: .monospaced))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 250)
                .onChange(of: verificationCode) { newValue in
                    if !useBackupCode {
                        verificationCode = newValue.filter { $0.isNumber }
                        if verificationCode.count > 6 {
                            verificationCode = String(verificationCode.prefix(6))
                        }
                    }
                }
                .onSubmit { Task {
                    await verify() }}
            
            // Toggle backup code
            Button {
                useBackupCode.toggle()
                verificationCode = ""
            } label: {
                Text(useBackupCode ? "Use Authenticator Code" : "Use Backup Code")
                    .font(.caption)
                    .foregroundColor(theme.badgeBackground)
            }
            .buttonStyle(.plain)
            
            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                
                Button("Verify") {
                    Task {
                        await
                        verify()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.badgeBackground)
                .disabled(verificationCode.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(30)
        .frame(width: 400)
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private func verify() async {
        guard await TwoFactorAuthManager.shared.verify(code: verificationCode, masterPassword: masterPassword) else {
            errorMessage = "Invalid code. Please try again."
            showError = true
            verificationCode = ""
            return
        }
        
        onSuccess()
    }
}
