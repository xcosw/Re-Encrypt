//
//  ClipboardSettingsSection.swift
//  re-Encrypt
//
//  Created by xcosw.dev on 5.12.2025.
//

import SwiftUI

// MARK: - Clipboard Settings Section

@available(macOS 15.0, *)
struct ClipboardSettingsSection: View {
    @EnvironmentObject private var theme: ThemeManager
    
    // ✅ Keep clearDelay as it's used by SecureClipboard
    @AppStorage("clearDelay") private var clearDelay: Int = 10
    
    // ✅ This can be removed if autoClearClipboard is no longer used
    // SecureClipboard ALWAYS auto-clears, so this toggle is now informational only
    @State private var isAlwaysSecure: Bool = true
    
    var body: some View {
        VStack(spacing: 20) {
            SettingsCard {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack(spacing: 12) {
                        Image(systemName: "shield.checkered")
                            .font(.title2)
                            .foregroundColor(theme.badgeBackground)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Clipboard Security")
                                .font(.headline)
                                .foregroundColor(theme.primaryTextColor)
                            
                            Text("Enterprise-grade clipboard protection")
                                .font(.subheadline)
                                .foregroundColor(theme.secondaryTextColor)
                        }
                    }
                    
                    Divider()
                    
                    // ✅ Security Status (Always On)
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.15))
                                .frame(width: 32, height: 32)
                            
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundColor(.green)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SecureClipboard Active")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(theme.primaryTextColor)
                            
                            Text("All clipboard operations are cryptographically secured")
                                .font(.caption)
                                .foregroundColor(theme.secondaryTextColor)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "lock.fill")
                            .foregroundColor(theme.badgeBackground)
                    }
                    .padding(12)
                    .background(Color.green.opacity(0.05))
                    .cornerRadius(8)
                    
                    Divider()
                    
                    // ✅ Auto-Clear Delay Setting
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "timer")
                                .foregroundColor(.purple)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto-Clear Delay")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(theme.primaryTextColor)
                                
                                Text("Time before clipboard is automatically cleared")
                                    .font(.caption)
                                    .foregroundColor(theme.secondaryTextColor)
                            }
                            
                            Spacer()
                        }
                        
                        // Delay control
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("\(clearDelay) seconds")
                                    .font(.subheadline.bold())
                                    .foregroundColor(theme.primaryTextColor)
                                    .frame(width: 80, alignment: .leading)
                                
                                Slider(value: Binding(
                                    get: { Double(clearDelay) },
                                    set: { clearDelay = Int($0) }
                                ), in: 5...60, step: 5)
                                
                                Text("60s")
                                    .font(.caption)
                                    .foregroundColor(theme.secondaryTextColor)
                                    .frame(width: 30)
                            }
                            
                            // Visual indicator
                            HStack(spacing: 4) {
                                Text("5s")
                                    .font(.caption2)
                                    .foregroundColor(theme.secondaryTextColor)
                                
                                Spacer()
                                
                                ForEach([10, 15, 30, 45], id: \.self) { value in
                                    Text("\(value)s")
                                        .font(.caption2)
                                        .foregroundColor(clearDelay == value ? theme.badgeBackground : theme.secondaryTextColor)
                                }
                                
                                Spacer()
                                
                                Text("60s")
                                    .font(.caption2)
                                    .foregroundColor(theme.secondaryTextColor)
                            }
                        }
                        .padding(12)
                        .background(theme.isDarkBackground ? Color.white.opacity(0.05) : Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                    }
                    
                    Divider()
                    
                    // ✅ Security Features Info
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Security Features")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(theme.primaryTextColor)
                        
                        FeatureBadge(
                            icon: "checkmark.seal.fill",
                            title: "HMAC Signature",
                            description: "Tamper detection using cryptographic signatures",
                            color: .blue
                        )
                        
                        FeatureBadge(
                            icon: "key.fill",
                            title: "Per-Entry Encryption",
                            description: "Unique encryption key for each password entry",
                            color: .purple
                        )
                        
                        FeatureBadge(
                            icon: "desktopcomputer",
                            title: "Device-Specific",
                            description: "Clipboard data only valid on this device",
                            color: .orange
                        )
                        
                        FeatureBadge(
                            icon: "clock.badge.checkmark",
                            title: "Timestamp Validation",
                            description: "Automatic detection of stale clipboard data",
                            color: .green
                        )
                        
                        FeatureBadge(
                            icon: "eye.slash.fill",
                            title: "Background Protection",
                            description: "Clipboard cleared when app goes to background",
                            color: .red
                        )
                    }
                    .padding(12)
                    .background(theme.isDarkBackground ? Color.white.opacity(0.03) : Color.secondary.opacity(0.03))
                    .cornerRadius(8)
                }
            }
        }
    }
}

// MARK: - Feature Badge Component

@available(macOS 15.0, *)
struct FeatureBadge: View {
    @EnvironmentObject private var theme: ThemeManager
    
    let icon: String
    let title: String
    let description: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 28, height: 28)
                
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundColor(theme.primaryTextColor)
                
                Text(description)
                    .font(.caption2)
                    .foregroundColor(theme.secondaryTextColor)
                    .lineLimit(2)
            }
            
            Spacer()
        }
    }
}
