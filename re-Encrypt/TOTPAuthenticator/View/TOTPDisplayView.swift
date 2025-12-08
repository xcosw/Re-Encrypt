import SwiftUI

// MARK: - TOTP Display View

@available(macOS 15.0, *)
struct TOTPDisplayView: View {
    @EnvironmentObject private var theme: ThemeManager
    
    let entry: PasswordEntry
    
    @State private var currentCode: String = "------"
    @State private var remainingSeconds: Int = 30
    @State private var progress: Double = 1.0
    @State private var timer: Timer?
    
    // ✅ Visual feedback for copy
    @State private var justCopied: Bool = false
    
    // ✅ User preference for auto-clear delay
    @AppStorage("clearDelay") private var clearDelay: Int = 10
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(theme.badgeBackground.opacity(0.15))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "clock.badge.checkmark")
                        .foregroundStyle(theme.badgeBackground.gradient)
                }
                
                // Code display
                VStack(alignment: .leading, spacing: 4) {
                    Text("Authenticator Code")
                        .font(.caption)
                        .foregroundColor(theme.secondaryTextColor)
                    
                    HStack(spacing: 8) {
                        Text(formatCode(currentCode))
                            .font(.system(.title3, design: .monospaced).bold())
                            .foregroundColor(theme.primaryTextColor)
                        
                        Button {
                            copyCodeSecurely()
                        } label: {
                            Image(systemName: justCopied ? "checkmark.circle.fill" : "doc.on.doc")
                                .foregroundColor(justCopied ? .green : theme.badgeBackground)
                                .animation(.easeInOut(duration: 0.2), value: justCopied)
                        }
                        .buttonStyle(.plain)
                        .help(justCopied ? "Copied!" : "Copy code")
                    }
                }
                
                Spacer()
                
                // Timer display
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 3)
                        .frame(width: 36, height: 36)
                    
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(progressColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 36, height: 36)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: progress)
                    
                    Text("\(remainingSeconds)")
                        .font(.caption.bold())
                        .foregroundColor(theme.primaryTextColor)
                }
            }
            .padding(12)
            .background(theme.adaptiveTileBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(theme.isDarkBackground ? Color.white.opacity(0.08) : Color.clear, lineWidth: 1)
            )
        }
        .onAppear {
            updateCode()
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
    }
    
    private var progressColor: Color {
        if remainingSeconds <= 5 {
            return .red
        } else if remainingSeconds <= 10 {
            return .orange
        } else {
            return theme.badgeBackground
        }
    }
    
    private func formatCode(_ code: String) -> String {
        guard code.count == 6 else { return code }
        let index = code.index(code.startIndex, offsetBy: 3)
        return "\(code[..<index]) \(code[index...])"
    }
    
    @MainActor
    private func updateCode() {
        if let code = entry.generateTOTPCode() {
            currentCode = code
        }
        remainingSeconds = TOTPGenerator.getRemainingSeconds()
        progress = TOTPGenerator.getProgress()
    }

    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                updateCode()
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - ✅ SECURE CLIPBOARD WITH VISUAL FEEDBACK
    
    /// Copies TOTP code using SecureClipboard with shorter timeout (TOTP codes expire quickly)
    private func copyCodeSecurely() {
        Task { @MainActor in
            // ✅ Use SecureClipboard with entry ID
            await SecureClipboard.shared.copy(
                text: currentCode,
                entryID: entry.id ?? UUID(),
                clearAfter: TimeInterval(min(30, clearDelay)) // Max 30 seconds for TOTP
            )
            
            // Show visual feedback
            justCopied = true
            
            // Reset feedback after 1.5 seconds
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            justCopied = false
        }
    }
}
