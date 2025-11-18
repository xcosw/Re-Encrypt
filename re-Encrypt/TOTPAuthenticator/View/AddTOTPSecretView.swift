import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - Add TOTP Secret View

struct AddTOTPSecretView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeManager
    
    let entry: PasswordEntry
    
    @State private var manualSecret = ""
    @State private var errorMessage: String?
    @State private var verificationCode = ""
    @State private var showVerification = false
    @State private var testSecret = ""
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(theme.badgeBackground.opacity(0.15))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "number.square.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(theme.badgeBackground.gradient)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Authenticator")
                        .font(.headline)
                        .foregroundColor(theme.primaryTextColor)
                    
                    Text("for \(entry.serviceName ?? "this service")")
                        .font(.caption)
                        .foregroundColor(theme.secondaryTextColor)
                }
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(theme.secondaryTextColor)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Content
            ScrollView {
                VStack(spacing: 20) {
                    manualEntrySection
                    
                    if showVerification {
                        verificationSection
                    }
                    
                    if let error = errorMessage {
                        errorView(error)
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer
            footer
        }
        .frame(width: 450, height: 500)
    }
    
    // MARK: - Manual Entry Section
    
    private var manualEntrySection: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard")
                .font(.system(size: 60))
                .foregroundStyle(theme.badgeBackground.gradient)
            
            Text("Enter Secret Key")
                .font(.title3.bold())
                .foregroundColor(theme.primaryTextColor)
            
            Text("Copy the secret key from your service and paste it below")
                .font(.subheadline)
                .foregroundColor(theme.secondaryTextColor)
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Secret Key")
                    .font(.caption)
                    .foregroundColor(theme.secondaryTextColor)
                
                TextField("Enter secret key", text: $manualSecret)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .textCase(.uppercase)
                    .onChange(of: manualSecret) { newValue in
                        manualSecret = newValue.uppercased()
                            .replacingOccurrences(of: " ", with: "")
                            .filter { $0.isLetter || $0.isNumber }
                    }
                
                Text("Format: XXXX XXXX XXXX XXXX (spaces optional)")
                    .font(.caption2)
                    .foregroundColor(theme.secondaryTextColor)
            }
            
            if !manualSecret.isEmpty && manualSecret.count >= 16 {
                Button {
                    testSecret = manualSecret
                    showVerification = true
                } label: {
                    Label("Test Secret", systemImage: "checkmark.shield")
                }
                .buttonStyle(.bordered)
            }
        }
    }
    
    // MARK: - Verification Section
    
    private var verificationSection: some View {
        VStack(spacing: 16) {
            Divider()
            
            Text("Verify Code")
                .font(.headline)
                .foregroundColor(theme.primaryTextColor)
            
            Text("Enter the 6-digit code from your authenticator to verify")
                .font(.caption)
                .foregroundColor(theme.secondaryTextColor)
                .multilineTextAlignment(.center)
            
            TextField("000000", text: $verificationCode)
                .textFieldStyle(.roundedBorder)
                .font(.system(.title3, design: .monospaced))
                .multilineTextAlignment(.center)
                .frame(width: 150)
                .onChange(of: verificationCode) { newValue in
                    verificationCode = newValue.filter { $0.isNumber }
                    if verificationCode.count > 6 {
                        verificationCode = String(verificationCode.prefix(6))
                    }
                }
        }
        .padding()
        .background(theme.badgeBackground.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Footer
    
    private var footer: some View {
        HStack(spacing: 12) {
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)
            
            Spacer()
            
            if showVerification {
                Button("Verify & Save") {
                    verifyAndSave()
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.badgeBackground)
                .disabled(verificationCode.count != 6)
            } else {
                Button("Continue") {
                    continueSetup()
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.badgeBackground)
                .disabled(manualSecret.count < 16)
            }
        }
        .padding()
    }
    
    // MARK: - Helper Views
    
    private func errorView(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(error)
                .foregroundColor(.red)
                .font(.caption)
        }
        .padding(12)
        .background(.red.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Actions
    
    private func continueSetup() {
        guard !manualSecret.isEmpty else {
            errorMessage = "Please enter a secret key"
            return
        }
        
        guard manualSecret.count >= 16 else {
            errorMessage = "Secret key is too short (minimum 16 characters)"
            return
        }
        
        testSecret = manualSecret
        showVerification = true
        errorMessage = nil
    }
    
    private func verifyAndSave() {
        guard verificationCode.count == 6 else {
            errorMessage = "Please enter a 6-digit code"
            return
        }
        
        // Generate code from secret and verify
        guard let generatedCode = TOTPGenerator.generateCode(secret: testSecret) else {
            errorMessage = "Invalid secret key format"
            return
        }
        
        guard generatedCode == verificationCode else {
            errorMessage = "Code doesn't match. Please check your authenticator app."
            return
        }
        
        // Save to entry
        let success = entry.setEncryptedTOTPSecret(testSecret, context: viewContext)
        
        if success {
            dismiss()
        } else {
            errorMessage = "Failed to save authenticator secret"
        }
    }
}
