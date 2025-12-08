import SwiftUI
import UniformTypeIdentifiers

struct GeneratePasswordView: View {
    @Binding var passwordData: Data
    @Binding var passwordDisplay: String
    var onGenerated: (Data) -> Void = { _ in }
    
    @State private var length: Double = 16
    @State private var includeLetters = true
    @State private var includeNumbers = true
    @State private var includeSymbols = false
    @State private var pronounceable = false
    @State private var usePattern = false
    @State private var pattern: String = "LLnnSS"
    @State private var strength: PasswordStrength = .medium
    @State private var recentPasswords: [String] = []
    
    @State private var excludeAmbiguous = false
    @State private var noRepeats = false
    @State private var requireAllTypes = false
    @State private var showCopiedAlert = false
    
    @Environment(\.dismiss) var dismiss
    
    // MARK: - Strength Enum
    enum PasswordStrength: String, CaseIterable, Identifiable {
        case light, medium, hard
        var id: String { rawValue }
        var description: String {
            switch self {
            case .light: return "Weak"
            case .medium: return "Medium"
            case .hard: return "Strong"
            }
        }
        var color: Color {
            switch self {
            case .light: return .red
            case .medium: return .orange
            case .hard: return .green
            }
        }
        var icon: String {
            switch self {
            case .light: return "exclamationmark.shield"
            case .medium: return "shield.lefthalf.filled"
            case .hard: return "checkmark.shield.fill"
            }
        }
    }
    
    // MARK: - View Body
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    passwordCard
                    configurationSection
                    if !recentPasswords.isEmpty { historySection }
                }
                .padding()
            }
        }
        .frame(minWidth: 500, minHeight: 600)
        .onAppear { generate() }
        .onChange(of: length) { oldvalue, _ in generate() }
        .onChange(of: includeLetters) {oldvalue,  _ in generate() }
        .onChange(of: includeNumbers) {oldvalue,  _ in generate() }
        .onChange(of: includeSymbols) {oldvalue,  _ in generate() }
        .onChange(of: pronounceable) {oldvalue,  _ in generate() }
        .onChange(of: usePattern) {oldvalue,  _ in generate() }
        .onChange(of: pattern) {oldvalue,  _ in generate() }
        .onChange(of: excludeAmbiguous) {oldvalue,  _ in generate() }
        .onChange(of: noRepeats) {oldvalue,  _ in generate() }
        .onChange(of: requireAllTypes) {oldvalue,  _ in generate() }
    }
    
    // MARK: - Header
    private var header: some View {
        HStack {
            Image(systemName: "lock.shield.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
            Text("Password Generator")
                .font(.title2.bold())
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Generated Password Card
    private var passwordCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "key.fill")
                    .foregroundColor(.accentColor)
                    .font(.title3)
                
                TextField("Generated Password", text: $passwordDisplay)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .disabled(true)
                    .textSelection(.enabled)
                
                HStack(spacing: 8) {
                    Button(action: copyPassword) {
                        Image(systemName: showCopiedAlert ? "checkmark" : "doc.on.doc.fill")
                            .foregroundColor(showCopiedAlert ? .green : .accentColor)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: generate) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                .font(.title3)
            }
            .padding()
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: strength.icon)
                        .foregroundColor(strength.color)
                    Text("Password Strength: \(strength.description)")
                        .font(.subheadline.bold())
                        .foregroundColor(strength.color)
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(strength.color)
                            .frame(width: geometry.size.width * passwordStrengthScore(), height: 8)
                            .animation(.easeInOut(duration: 0.3), value: strength)
                    }
                }
                .frame(height: 8)
            }
            .padding()
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
    
    // MARK: - Configuration Section
    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Configuration", systemImage: "slider.horizontal.3")
                .font(.headline)
            
            if !usePattern {
                lengthSlider
            }
            
            VStack(spacing: 12) {
                ToggleRow(icon: "textformat.abc", title: "Include Letters", isOn: $includeLetters)
                ToggleRow(icon: "number", title: "Include Numbers", isOn: $includeNumbers)
                ToggleRow(icon: "at.badge.plus", title: "Include Symbols", isOn: $includeSymbols)
                ToggleRow(icon: "speaker.wave.2", title: "Pronounceable", isOn: $pronounceable)
                ToggleRow(icon: "rectangle.grid.1x2", title: "Use Pattern", isOn: $usePattern)
            }
            
            if usePattern {
                patternInput
            }
            
            Divider()
            
            Label("Advanced Options", systemImage: "gearshape.2")
                .font(.headline)
            
            VStack(spacing: 12) {
                ToggleRow(icon: "eye.slash", title: "Exclude ambiguous characters", isOn: $excludeAmbiguous)
                ToggleRow(icon: "repeat.circle", title: "Avoid repeating characters", isOn: $noRepeats)
                ToggleRow(icon: "checkmark.circle", title: "Require at least one of each type", isOn: $requireAllTypes)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
    
    private var lengthSlider: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "ruler")
                    .foregroundColor(.secondary)
                Text("Password Length")
                    .font(.subheadline)
                Spacer()
                Text("\(Int(length))")
                    .font(.subheadline.bold())
                    .foregroundColor(.accentColor)
            }
            Slider(value: $length, in: 8...64, step: 1)
                .accentColor(.accentColor)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var patternInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "aspectratio")
                    .foregroundColor(.secondary)
                Text("Pattern")
                    .font(.subheadline)
            }
            TextField("e.g., LLnnSS", text: $pattern)
                .textFieldStyle(.roundedBorder)
            Text("L=Upper, l=lower, n=number, S=symbol")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    // MARK: - History Section
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Recent Passwords", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
                Button {
                    recentPasswords.removeAll()
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
            
            ForEach(recentPasswords, id: \.self) { pwd in
                HStack(spacing: 12) {
                    Image(systemName: "key")
                        .foregroundColor(.secondary)
                    Text(pwd)
                        .font(.system(.callout, design: .monospaced))
                        .lineLimit(1)
                    Spacer()
                    Button {
                        copyToClipboard(pwd)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
    
    // MARK: - Logic
    private func generate() {
        let pwd: String
        if usePattern {
            pwd = generatePatternPassword(pattern: pattern)
        } else if pronounceable {
            pwd = pronounceablePassword(length: Int(length))
        } else {
            pwd = randomPassword(
                length: Int(length),
                useLetters: includeLetters,
                useNumbers: includeNumbers,
                useSymbols: includeSymbols
            )

        }
        
        passwordDisplay = pwd
        passwordData = Data(pwd.utf8)  // ✅ Securely update Data binding
        strength = estimateStrength(pwd)
        saveToHistory(pwd)
    }
    
    private func generatePatternPassword(pattern: String) -> String {
        pattern.map { char in
            switch char {
            case "L": return letters().uppercased().randomElement()!
            case "l": return letters().lowercased().randomElement()!
            case "n": return numbers().randomElement()!
            case "S": return symbols().randomElement()!
            default: return char
            }
        }.map(String.init).joined()
    }
    
    private func randomPassword(
        length: Int,
        useLetters: Bool,
        useNumbers: Bool,
        useSymbols: Bool
    ) -> String {
        var chars = ""
        if useLetters { chars += self.letters() }
        if useNumbers { chars += self.numbers() }
        if useSymbols { chars += self.symbols() }
        
        if excludeAmbiguous {
            chars.removeAll { "O0oIl1|" .contains($0) }
        }
        
        guard !chars.isEmpty else { return "" }
        
        var password = ""
        var usedChars = Set<Character>()
        
        if requireAllTypes {
            if useLetters { addChar(from: letters(), to: &password, used: &usedChars) }
            if useNumbers { addChar(from: numbers(), to: &password, used: &usedChars) }
            if useSymbols { addChar(from: symbols(), to: &password, used: &usedChars) }
        }
        
        while password.count < length {
            guard let c = chars.randomElement() else { break }
            if noRepeats && usedChars.contains(c) { continue }
            password.append(c)
            if noRepeats { usedChars.insert(c) }
        }
        
        return String(password.shuffled())
    }

    
    private func addChar(from source: String, to password: inout String, used: inout Set<Character>) {
        let c = source.randomElement()!
        password.append(c)
        used.insert(c)
    }
    
    private func pronounceablePassword(length: Int) -> String {
        let vowels = "aeiou"
        let consonants = "bcdfghjklmnpqrstvwxyz"
        return (0..<length).map { $0 % 2 == 0 ? consonants.randomElement()! : vowels.randomElement()! }.map(String.init).joined()
    }
    
    private func estimateStrength(_ password: String) -> PasswordStrength {
        var score = 0
        if password.rangeOfCharacter(from: .lowercaseLetters) != nil { score += 1 }
        if password.rangeOfCharacter(from: .uppercaseLetters) != nil { score += 1 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil { score += 1 }
        if password.rangeOfCharacter(from: CharacterSet(charactersIn: symbols())) != nil { score += 1 }
        if password.count >= 12 { score += 1 }
        
        switch score {
        case 0...2: return .light
        case 3...4: return .medium
        default: return .hard
        }
    }
    
    private func passwordStrengthScore() -> Double {
        switch strength {
        case .light: return 0.3
        case .medium: return 0.6
        case .hard: return 1.0
        }
    }
    
    private func copyPassword() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(passwordDisplay, forType: .string)
        showCopiedAlert = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopiedAlert = false
        }
    }
    
    private func copyToClipboard(_ pwd: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pwd, forType: .string)
    }
    
    private func saveToHistory(_ pwd: String) {
        if !recentPasswords.contains(pwd) {
            recentPasswords.insert(pwd, at: 0)
            if recentPasswords.count > 10 { recentPasswords.removeLast() }
        }
    }
    
    private func letters() -> String { "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ" }
    private func numbers() -> String { "0123456789" }
    private func symbols() -> String { "!@#$%^&*()-_=+[]{}|;:,.<>?/`~" }
}


// MARK: - Toggle Row Component
struct ToggleRow: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            Text(title)
                .font(.subheadline)
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }
}
