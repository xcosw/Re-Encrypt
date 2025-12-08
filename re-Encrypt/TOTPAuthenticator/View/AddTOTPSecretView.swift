import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - Add TOTP Secret View

@available(macOS 15.0, *)
struct AddTOTPSecretView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeManager
    
    let entry: PasswordEntry
    
    @State private var manualSecret = ""
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 24) {
            
            // Header
            header
            
            Divider()
            
            // Content
            ScrollView {
                VStack(spacing: 20) {
                    manualEntrySection
                    
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
        .frame(width: 450, height: 430)
    }
    
    // MARK: - Header
    
    private var header: some View {
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
                
                Text("Example: JBSWY3DPEHPK3PXP (spaces optional)")
                    .font(.caption2)
                    .foregroundColor(theme.secondaryTextColor)
            }
        }
    }
    
    // MARK: - Footer
    
    private var footer: some View {
        HStack(spacing: 12) {
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)
            
            Spacer()
            
            Button("Save Secret") {
                saveSecret()
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.badgeBackground)
            .disabled(manualSecret.count < 16)
        }
        .padding()
    }
    
    // MARK: - Error View
    
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
    
    // MARK: - Save TOTP Secret
    
    private func saveSecret() {
        guard manualSecret.count >= 16 else {
            errorMessage = "Secret key is too short (minimum 16 characters)"
            return
        }
        
        let success = entry.setEncryptedTOTPSecret(manualSecret, context: viewContext)
        
        if success {
            dismiss()
        } else {
            errorMessage = "Failed to save authenticator secret."
        }
    }
}
