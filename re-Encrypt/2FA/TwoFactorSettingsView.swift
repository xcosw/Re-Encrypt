import SwiftUI
import CoreData

@available(macOS 15.0, *)
struct TwoFactorSettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var theme: ThemeManager
    
    @State private var isEnabled = TwoFactorAuthManager.shared.isEnabled
    @State private var showSetupSheet = false
    @State private var showDisableConfirm = false
    @State private var showBackupCodesSheet = false
    @State private var showPasswordPrompt = false
    @State private var masterPassword = ""
    @State private var backupCodes: [String] = []
    @State private var showError = false
    @State private var errorMessage = ""
    
    enum ActionType {
        case disable
        case viewCodes
        case regenerateCodes
    }
    @State private var pendingAction: ActionType?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Two-Factor Authentication")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(theme.primaryTextColor)
                    
                    Text("Add an extra layer of security to your account")
                        .font(.caption)
                        .foregroundColor(theme.secondaryTextColor)
                }
                
                Spacer()
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Status card
                    statusCard
                    
                    // Info section
                    if isEnabled {
                        enabledOptions
                    } else {
                        setupInstructions
                    }
                }
                .padding()
            }
        }
        .sheet(isPresented: $showSetupSheet) {
            TwoFactorSetupView()
                .environmentObject(theme)
                .environment(\.managedObjectContext, viewContext)
                .onDisappear {
                    isEnabled = TwoFactorAuthManager.shared.isEnabled
                }
        }
        .sheet(isPresented: $showBackupCodesSheet) {
            BackupCodesView(codes: backupCodes)
                .environmentObject(theme)
        }
        .sheet(isPresented: $showPasswordPrompt) {
            PasswordPromptView(
                masterPassword: $masterPassword,
                onConfirm: {
                    Task { @MainActor
                      in await handlePendingAction()
                    }
                },
                onCancel: {
                    showPasswordPrompt = false
                    pendingAction = nil
                }
            )
            .environmentObject(theme)
        }
        .alert("Disable 2FA?", isPresented: $showDisableConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Disable", role: .destructive) {
                promptForPassword(action: .disable)
            }
        } message: {
            Text("This will remove two-factor authentication from your account. You can re-enable it at any time.")
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Status Card
    
    private var statusCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(isEnabled ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                    .frame(width: 50, height: 50)
                
                Image(systemName: isEnabled ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 24))
                    .foregroundColor(isEnabled ? .green : .orange)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(isEnabled ? "2FA Enabled" : "2FA Disabled")
                    .font(.headline)
                    .foregroundColor(theme.primaryTextColor)
                
                Text(isEnabled ? "Your account is protected" : "Enable for enhanced security")
                    .font(.caption)
                    .foregroundColor(theme.secondaryTextColor)
            }
            
            Spacer()
            
            if isEnabled {
                Button("Disable") {
                    showDisableConfirm = true
                }
                .buttonStyle(.bordered)
                .tint(.red)
            } else {
                Button("Enable 2FA") {
                    showSetupSheet = true
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.badgeBackground)
            }
        }
        .padding()
        .background(theme.adaptiveTileBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(theme.isDarkBackground ? Color.white.opacity(0.08) : Color.clear, lineWidth: 1)
        )
    }
    
    // MARK: - Setup Instructions
    
    private var setupInstructions: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What is Two-Factor Authentication?")
                .font(.headline)
                .foregroundColor(theme.primaryTextColor)
            
            Text("Two-factor authentication (2FA) adds an extra layer of security to your account by requiring a verification code in addition to your master password when signing in.")
                .font(.subheadline)
                .foregroundColor(theme.secondaryTextColor)
            
            Divider()
            
            Text("How it works:")
                .font(.headline)
                .foregroundColor(theme.primaryTextColor)
            
            VStack(alignment: .leading, spacing: 12) {
                FeaturesRow(
                    icon: "1.circle.fill",
                    title: "Install an authenticator app",
                    description: "Use Any Authenticator App, Authy, 1Password, or similar"
                )
                
                FeaturesRow(
                    icon: "2.circle.fill",
                    title: "Scan the QR code",
                    description: "Link your account to the authenticator app"
                )
                
                FeaturesRow(
                    icon: "3.circle.fill",
                    title: "Enter the code",
                    description: "Use the 6-digit code from your app to sign in"
                )
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text("Backup Codes")
                        .font(.headline)
                        .foregroundColor(theme.primaryTextColor)
                }
                
                Text("You'll receive backup codes during setup. Keep them safe - each can be used once if you lose access to your authenticator app.")
                    .font(.caption)
                    .foregroundColor(theme.secondaryTextColor)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
        .padding()
        .background(theme.adaptiveTileBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(theme.isDarkBackground ? Color.white.opacity(0.08) : Color.clear, lineWidth: 1)
        )
    }
    
    // MARK: - Enabled Options
    
    private var enabledOptions: some View {
        VStack(spacing: 12) {
            OptionButton(
                icon: "doc.text.fill",
                title: "View Backup Codes",
                description: "See your remaining backup codes",
                action: { promptForPassword(action: .viewCodes) }
            )
            
            OptionButton(
                icon: "arrow.clockwise.circle.fill",
                title: "Regenerate Backup Codes",
                description: "Get new backup codes (old ones will be invalidated)",
                action: { promptForPassword(action: .regenerateCodes) }
            )
        }
        .padding()
        .background(theme.adaptiveTileBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(theme.isDarkBackground ? Color.white.opacity(0.08) : Color.clear, lineWidth: 1)
        )
    }
    
    // MARK: - Actions
    
    private func promptForPassword(action: ActionType) {
        pendingAction = action
        masterPassword = ""
        showPasswordPrompt = true
    }
    
    @MainActor
    private func handlePendingAction() async {
        let passwordData = Data(masterPassword.utf8)
        var passwordCopy = passwordData
        defer {
            passwordCopy.secureWipe()
            masterPassword = "" // Clear UI
        }
        
        guard await CryptoHelper.verifyMasterPassword(password: passwordData, context: viewContext) else {
            errorMessage = "Incorrect master password"
            showError = true
            showPasswordPrompt = false
            return
        }
        
        switch pendingAction {
        case .disable:
            await disableTwoFactor(passwordData: passwordData)
        case .viewCodes:
            await viewBackupCodes(passwordData: passwordData)
        case .regenerateCodes:
            await regenerateBackupCodes(passwordData: passwordData)
        case .none:
            break
        }
        
        showPasswordPrompt = false
        pendingAction = nil
    }
    
    private func disableTwoFactor(passwordData: Data) async {
        guard await TwoFactorAuthManager.shared.disable(masterPassword: passwordData, context: viewContext) else {
            errorMessage = "Failed to disable 2FA"
            showError = true
            return
        }
        
        isEnabled = false
    }
    
    private func viewBackupCodes(passwordData: Data) async {
        guard let codes = await TwoFactorAuthManager.shared.getRemainingBackupCodes(masterPassword: passwordData) else {
            errorMessage = "Failed to retrieve backup codes"
            showError = true
            return
        }
        
        backupCodes = codes
        showBackupCodesSheet = true
    }
    
    private func regenerateBackupCodes(passwordData: Data) async {
        guard let codes = await TwoFactorAuthManager.shared.regenerateBackupCodes(masterPassword: passwordData) else {
            errorMessage = "Failed to regenerate backup codes"
            showError = true
            return
        }
        
        backupCodes = codes
        showBackupCodesSheet = true
    }
}

// MARK: - Feature Row

struct FeaturesRow: View {
    @EnvironmentObject private var theme: ThemeManager
    
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(theme.badgeBackground)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(theme.primaryTextColor)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(theme.secondaryTextColor)
            }
        }
    }
}

// MARK: - Option Button

struct OptionButton: View {
    @EnvironmentObject private var theme: ThemeManager
    
    let icon: String
    let title: String
    let description: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(theme.badgeBackground)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(theme.primaryTextColor)
                    
                    Text(description)
                        .font(.caption)
                        .foregroundColor(theme.secondaryTextColor)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(theme.secondaryTextColor)
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Password Prompt View

struct PasswordPromptView: View {
    @EnvironmentObject private var theme: ThemeManager
    @Binding var masterPassword: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 50))
                .foregroundStyle(theme.badgeBackground.gradient)
            
            Text("Verify Master Password")
                .font(.title2.weight(.semibold))
                .foregroundColor(theme.primaryTextColor)
            
            SecureField("Master Password", text: $masterPassword)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)
                .onSubmit(onConfirm)
            
            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                
                Button("Confirm", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(theme.badgeBackground)
                    .disabled(masterPassword.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(30)
        .frame(width: 350)
    }
}

// MARK: - Backup Codes View

struct BackupCodesView: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.dismiss) private var dismiss
    
    let codes: [String]
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Backup Codes")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(theme.primaryTextColor)
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(theme.secondaryTextColor)
                }
                .buttonStyle(.plain)
            }
            
            Text(codes.isEmpty ? "No backup codes remaining" : "Each code can be used once")
                .font(.caption)
                .foregroundColor(theme.secondaryTextColor)
            
            if codes.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    
                    Text("All backup codes have been used")
                        .font(.headline)
                        .foregroundColor(theme.primaryTextColor)
                    
                    Text("Generate new codes to regain backup access")
                        .font(.caption)
                        .foregroundColor(theme.secondaryTextColor)
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(codes.enumerated()), id: \.offset) { index, code in
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
                }
                
                Button {
                    copyAllCodes()
                } label: {
                    Label("Copy All Codes", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.badgeBackground)
            }
        }
        .padding()
        .frame(width: 400, height: 500)
    }
    
    private func copyAllCodes() {
        let allCodes = codes.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(allCodes, forType: .string)
    }
}
