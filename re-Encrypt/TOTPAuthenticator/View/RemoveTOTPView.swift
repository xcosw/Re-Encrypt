import SwiftUI

// MARK: - Remove TOTP Confirmation

@available(macOS 15.0, *)
struct RemoveTOTPView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeManager
    
    let entry: PasswordEntry
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text("Remove Authenticator?")
                .font(.title2.bold())
                .foregroundColor(theme.primaryTextColor)
            
            Text("This will remove the 2FA code for \(entry.serviceName ?? "this service"). You can add it back later.")
                .font(.subheadline)
                .foregroundColor(theme.secondaryTextColor)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Remove", role: .destructive) {
                    if entry.removeTOTPSecret(context: viewContext) {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(30)
        .frame(width: 350)
    }
}

