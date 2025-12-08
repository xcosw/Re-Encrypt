//
//  DeviceBindingSettingsView.swift
//  re-Encrypt
//
//  Created by xcosw.dev on 4.12.2025.
//
/*
import SwiftUI

@available(macOS 15.0, *)
struct DeviceBindingSettingsView: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var deviceBindingEnabled: Bool = true
    @State private var isChanging = false
    @State private var showConfirmation = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            headerView
            
            // Current Status
            statusCard
            
            // Toggle Section
            toggleSection
            
            // Information Section
            infoSection
            
            if let error = errorMessage {
                errorView(error)
            }
            
            Spacer()
        }
        .padding()
        .background(theme.backgroundColor.ignoresSafeArea())
        .onAppear {
            deviceBindingEnabled = CryptoHelper.getDeviceBindingEnabled()
        }
        .alert("Change Device Binding?", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Re-encrypt All Data", role: .destructive) {
                Task {
                    await changeDeviceBinding()
                }
            }
        } message: {
            Text(deviceBindingEnabled
                ? "This will re-encrypt all passwords WITHOUT device binding. They can be moved to other devices."
                : "This will re-encrypt all passwords WITH device binding. They will only work on this device.")
        }
        .alert("Success", isPresented: $showSuccess) {
            Button("OK") { }
        } message: {
            Text("All passwords have been re-encrypted with the new device binding setting.")
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(theme.badgeBackground.gradient)
            
            Text("Device Binding")
                .font(.title2.bold())
                .foregroundColor(theme.primaryTextColor)
            
            Text("Control whether your encrypted data is tied to this device")
                .font(.subheadline)
                .foregroundColor(theme.secondaryTextColor)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 8)
    }
    
    // MARK: - Status Card
    
    private var statusCard: some View {
        HStack(spacing: 12) {
            Image(systemName: deviceBindingEnabled ? "checkmark.shield.fill" : "xmark.shield.fill")
                .font(.title)
                .foregroundColor(deviceBindingEnabled ? .green : .orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Status")
                    .font(.caption)
                    .foregroundColor(theme.secondaryTextColor)
                
                Text(deviceBindingEnabled ? "Device Binding Enabled" : "Device Binding Disabled")
                    .font(.headline)
                    .foregroundColor(theme.primaryTextColor)
                
                Text(deviceBindingEnabled
                    ? "Passwords work only on this device"
                    : "Passwords can be moved between devices")
                    .font(.caption)
                    .foregroundColor(theme.secondaryTextColor)
            }
            
            Spacer()
        }
        .padding()
        .background(theme.tileBackground)
        .cornerRadius(12)
    }
    
    // MARK: - Toggle Section
    
    private var toggleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(
                get: { deviceBindingEnabled },
                set: { newValue in
                    if newValue != deviceBindingEnabled {
                        showConfirmation = true
                    }
                }
            )) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable Device Binding")
                            .font(.headline)
                            .foregroundColor(theme.primaryTextColor)
                        
                        Text("Requires vault to be unlocked")
                            .font(.caption)
                            .foregroundColor(theme.secondaryTextColor)
                    }
                    
                    if isChanging {
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
            }
            .toggleStyle(.switch)
            .disabled(isChanging || !CryptoHelper.isUnlocked)
            .padding()
            .background(theme.selectionFill)
            .cornerRadius(10)
            
            if !CryptoHelper.isUnlocked {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.orange)
                    Text("Unlock your vault to change this setting")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Info Section
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("How Device Binding Works")
            
            infoRow(
                icon: "shield.checkered",
                title: "With Device Binding (Recommended)",
                description: "Passwords are encrypted with device-specific data. If someone copies your encrypted files to another device, they cannot decrypt them.",
                color: .green
            )
            
            infoRow(
                icon: "arrow.triangle.swap",
                title: "Without Device Binding",
                description: "Passwords can be decrypted on any device with your master password. Useful for syncing across devices, but less secure if files are stolen.",
                color: .orange
            )
            
            Divider()
            
            sectionHeader("Important Notes")
            
            noteRow(
                icon: "exclamationmark.triangle.fill",
                text: "Changing this setting will re-encrypt ALL passwords",
                color: .orange
            )
            
            noteRow(
                icon: "clock.fill",
                text: "Re-encryption may take a moment for large vaults",
                color: .blue
            )
            
            noteRow(
                icon: "lock.fill",
                text: "Your vault must be unlocked to change this setting",
                color: theme.badgeBackground
            )
        }
        .padding()
        .background(theme.tileBackground)
        .cornerRadius(12)
    }
    
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundColor(theme.primaryTextColor)
    }
    
    private func infoRow(icon: String, title: String, description: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundColor(theme.primaryTextColor)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(theme.secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    private func noteRow(icon: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            
            Text(text)
                .font(.caption)
                .foregroundColor(theme.secondaryTextColor)
        }
    }
    
    private func errorView(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(error)
                .foregroundColor(.red)
                .font(.subheadline)
        }
        .padding()
        .background(.red.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Change Device Binding
    
    private func changeDeviceBinding() async {
        guard CryptoHelper.isUnlocked else {
            errorMessage = "Vault must be unlocked to change device binding"
            return
        }
        
        isChanging = true
        errorMessage = nil
        
        let newValue = !deviceBindingEnabled
        
        let success = await CryptoHelper.setDeviceBindingEnabled(newValue, context: viewContext)
        
        await MainActor.run {
            isChanging = false
            
            if success {
                deviceBindingEnabled = newValue
                showSuccess = true
            } else {
                errorMessage = "Failed to change device binding. Please try again."
            }
            
            // Clear error after 5 seconds
            if errorMessage != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    errorMessage = nil
                }
            }
        }
    }
}
*/
