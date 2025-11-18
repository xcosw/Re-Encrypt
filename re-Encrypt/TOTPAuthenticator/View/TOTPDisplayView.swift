import SwiftUI

// MARK: - TOTP Display View

struct TOTPDisplayView: View {
    @EnvironmentObject private var theme: ThemeManager
    
    let entry: PasswordEntry
    
    @State private var currentCode: String = "------"
    @State private var remainingSeconds: Int = 30
    @State private var progress: Double = 1.0
    @State private var timer: Timer?
    
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
                            copyToClipboard(currentCode)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .foregroundColor(theme.badgeBackground)
                        }
                        .buttonStyle(.plain)
                        .help("Copy code")
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
    
    private func updateCode() {
        if let code = entry.generateTOTPCode() {
            currentCode = code
        }
        remainingSeconds = TOTPGenerator.getRemainingSeconds()
        progress = TOTPGenerator.getProgress()
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateCode()
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        
        // Auto-clear after 30 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            NSPasteboard.general.clearContents()
        }
    }
}

