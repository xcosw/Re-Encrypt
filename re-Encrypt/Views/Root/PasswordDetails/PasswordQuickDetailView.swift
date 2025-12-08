//
//  PasswordQuickDetailView.swift
//  re-Encrypt
//
//  Created by xcosw.dev on 2.12.2025.
//


import SwiftUI
import CryptoKit

@available(macOS 15.0, *)
struct PasswordQuickDetailView: View {
    let entry: PasswordEntry
    
    @EnvironmentObject private var theme: ThemeManager
    
    @State private var currentTOTP = "------"
    @State private var timeRemaining = 30
    @State private var progress: CGFloat = 1.0
    
    // Use your existing TOTPGenerator (no instance needed)
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 40) {
            // Service Icon + Name
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(serviceColor.opacity(0.15))
                        .frame(width: 100, height: 100)
                    
                    Circle()
                        .stroke(serviceColor.opacity(0.4), lineWidth: 3)
                        .frame(width: 100, height: 100)
                    
                    if let char = entry.serviceName?.first {
                        Text(String(char).uppercased())
                            .font(.system(size: 44, weight: .bold))
                            .foregroundColor(serviceColor)
                    }
                }
                
                Text(entry.serviceName ?? "Unknown")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
            }
            
            // Email / Username
            if let username = entry.username, !username.isEmpty {
                Label(username, systemImage: "envelope.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            
            // 2FA Hero Section
            if entry.hasTwoFactor {
                VStack(spacing: 28) {
                    Text(currentTOTP)
                        .font(.system(size: 56, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeInOut, value: currentTOTP)
                    
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 8)
                            .frame(width: 120, height: 120)
                        
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(theme.badgeBackground.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.5), value: progress)
                        
                        Text("\(timeRemaining)s")
                            .font(.title2.bold())
                            .foregroundColor(theme.badgeBackground)
                    }
                    
                    Button {
                        let cleanCode = currentTOTP.replacingOccurrences(of: " ", with: "")
                        NSPasteboard.general.setString(cleanCode, forType: .string)
                        
                       
                    } label: {
                        Label("Copy Code", systemImage: "doc.on.doc.fill")
                            .font(.title3.bold())
                            .frame(maxWidth: 300)
                            .padding()
                            .background(theme.badgeBackground.gradient)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(40)
                .background(theme.adaptiveTileBackground, in: RoundedRectangle(cornerRadius: 28))
                .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(theme.badgeBackground.opacity(0.3), lineWidth: 2))
            } else {
                Text("No 2FA configured")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appBackground()
        .onReceive(timer) { _ in
            updateTOTP()
        }
        .onAppear {
            updateTOTP()
        }
    }
    
    // MARK: - Brand Colors (same as your list view)
    private let brandColors: [String: Color] = [
        "Google": Color(red: 66/255, green: 133/255, blue: 244/255),
        "Apple": Color(red: 0, green: 0, blue: 0),
        "GitHub": Color(red: 36/255, green: 41/255, blue: 47/255),
        "Microsoft": Color(red: 242/255, green: 80/255, blue: 34/255),
        "Amazon": Color(red: 255/255, green: 153/255, blue: 0/255),
        "Netflix": Color(red: 229/255, green: 9/255, blue: 20/255),
        "Spotify": Color(red: 30/255, green: 215/255, blue: 96/255),
        "Discord": Color(red: 88/255, green: 101/255, blue: 242/255),
        "ProtonMail": Color(red: 88/255, green: 75/255, blue: 141/255),
        "Bitwarden": Color(red: 0/255, green: 82/255, blue: 204/255),
        "1Password": Color(red: 0/255, green: 122/255, blue: 255/255),
        // Add more as needed...
        "": .accentColor // fallback
    ]
    
    private var serviceColor: Color {
        brandColors[entry.serviceName ?? ""] ?? .accentColor
    }
    
    // MARK: - TOTP Update Logic (uses your TOTPGenerator)
    private func updateTOTP() {
        guard entry.hasTwoFactor else {
            currentTOTP = "------"
            timeRemaining = 0
            progress = 0
            return
        }
        
        guard let secData = entry.getDecryptedTOTPSecret() else {
            currentTOTP = "------"
            timeRemaining = 0
            progress = 0
            return
        }
        defer { secData.clear() }
        
        // Convert SecData to String for TOTP generation
        let secret = secData.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return "" }
            let data = Data(bytes: base, count: ptr.count)
            return String(data: data, encoding: .utf8) ?? ""
        }
        
        guard let code = TOTPGenerator.generateCode(secret: secret) else {
            currentTOTP = "------"
            timeRemaining = 0
            progress = 0
            return
        }
        
        let remaining = TOTPGenerator.getRemainingSeconds()
        let newCode = code.grouped()
        
        // Only animate when code actually changes (every 30s)
        if newCode != currentTOTP {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentTOTP = newCode
            }
        }
        
        withAnimation(.linear(duration: 0.5)) {
            timeRemaining = remaining
            progress = CGFloat(remaining) / 30.0
        }
    }
}

// MARK: - Helper: Group digits (123456 → 123 456)
extension String {
    func grouped() -> String {
        let clean = self.replacingOccurrences(of: " ", with: "")
        return clean.enumerated().map { $0.offset % 3 == 0 && $0.offset > 0 ? " \($0.element)" : String($0.element) }.joined()
    }
}
