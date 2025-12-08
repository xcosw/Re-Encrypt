// MARK: - Security Status Indicator View

import SwiftUI


 // MARK: - Security Status Indicator

@available(macOS 15.0, *)
struct SecurityStatusIndicator: View {
     @EnvironmentObject private var theme: ThemeManager
     @State private var showPopover = false
     
     var body: some View {
         Button {
             showPopover.toggle()
         } label: {
             HStack(spacing: 6) {
                 Image(systemName: CryptoHelper.isUnlocked ? "checkmark.shield.fill" : "lock.shield.fill")
                     .foregroundColor(CryptoHelper.isUnlocked ? .green : .orange)
                 Text(CryptoHelper.isUnlocked ? "Unlocked" : "Locked")
                     .font(.caption)
                     .foregroundColor(theme.secondaryTextColor)
             }
             .padding(.horizontal, 12)
             .padding(.vertical, 6)
             .background(Color.secondary.opacity(0.1))
             .cornerRadius(8)
         }
         .buttonStyle(.plain)
         .popover(isPresented: $showPopover) {
             SecurityInfoView()
                 .environmentObject(theme)
         }
     }
 }

@available(macOS 15.0, *)
struct SecurityInfoView: View {
     @EnvironmentObject private var theme: ThemeManager
     @State private var failedAttempts: Int = 0
     @State private var autoLockEnabled: Bool = false
     @State private var biometricEnabled: Bool = false
     
     var body: some View {
         VStack(alignment: .leading, spacing: 12) {
             Text("Security Status")
                 .font(.headline)
                 .foregroundColor(theme.primaryTextColor)
             
             Divider()
             
             InfoRow(label: "Session", value: CryptoHelper.isUnlocked ? "Active" : "Locked")
         
             InfoRow(label: "Failed Attempts", value: "\(failedAttempts)/\(CryptoHelper.maxAttempts)")
             
             Divider()
             
             Text("Protection Features")
                 .font(.subheadline)
                 .fontWeight(.semibold)
                 .foregroundColor(theme.primaryTextColor)
             
             FeatureRow(name: "Memory Protection", enabled: true)
             FeatureRow(name: "Secure Deletion", enabled: true)
             FeatureRow(name: "Auto-Lock", enabled: autoLockEnabled)
             FeatureRow(name: "Biometric Auth", enabled: biometricEnabled)
         }
         .padding()
         .frame(width: 300)
         .onAppear {
             loadSecurityInfo()
         }
     }
     
     private func loadSecurityInfo() {
         failedAttempts = CryptoHelper.failedAttempts
         autoLockEnabled = CryptoHelper.getAutoLockEnabled()
         biometricEnabled = CryptoHelper.biometricUnlockEnabled
     }
 }

 struct InfoRow: View {
     @EnvironmentObject private var theme: ThemeManager
     let label: String
     let value: String
     
     var body: some View {
         HStack {
             Text(label)
                 .foregroundColor(theme.secondaryTextColor)
             Spacer()
             Text(value)
                 .fontWeight(.semibold)
                 .foregroundColor(theme.primaryTextColor)
         }
         .font(.caption)
     }
 }

 struct FeatureRow: View {
     let name: String
     let enabled: Bool
     
     var body: some View {
         HStack {
             Image(systemName: enabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                 .foregroundColor(enabled ? .green : .red)
             Text(name)
                 .font(.caption)
         }
     }
 }
