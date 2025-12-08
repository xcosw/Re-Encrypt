/*
import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

@available(macOS 15.0, *)
@MainActor
final class EditablePassword {
    var serviceName: String = ""
    var username: String = ""
    var lgdata: String = ""
    var phn: String = ""
    var website: String = ""
    var password: String = ""
    var notes: String = ""
    var isFavorite: Bool = false
    var tags: [String] = []
    
    static var empty: EditablePassword { EditablePassword() }
    
    init(entry: PasswordEntry) {
        self.serviceName = entry.serviceName ?? ""
        self.username = entry.username ?? ""
        self.lgdata = entry.lgdata ?? ""
        self.phn = entry.phn ?? ""
        self.website = entry.website ?? ""
        self.password = ""
        
        // SAFE: Use nil-coalescing for optional fields
        self.notes = entry.notes ?? ""
        self.isFavorite = entry.isFavorite
        
        // SAFE: Use the safe tag accessor
        self.tags = entry.safeTagArray
    }
    
    init() {}
}

@available(macOS 15.0, *)
struct PasswordDetailsView: View {
    var selectedPassword: PasswordEntry?
    var decrypt: (PasswordEntry) -> String?
    var onEdit: (PasswordEntry) -> Void
    var onDelete: (PasswordEntry) -> Void
    
    @State private var decryptedData = Data()
    @State private var showPassword: Bool = false
    @State private var hidePasswordTask: Task<Void, Never>? = nil
    
    @State private var isEditing: Bool = false
    @State private var editableEntry: EditablePassword = .empty
    
    @AppStorage("autoClearClipboard") private var autoClearClipboard: Bool = true
    @AppStorage("clearDelay") private var clearDelay: Int = 10
    @AppStorage("RevealTimeoutSeconds") private var revealTimeout: Int = 5
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var theme: ThemeManager
    
    @State private var showWiFiQRPopover: Bool = false
    @State private var showDeleteConfirm: Bool = false
    
    // 2FA states
    @State private var showAddTOTP = false
    @State private var showRemoveTOTP = false
    
    private var isWiFiEntry: Bool {
        guard let e = selectedPassword else { return false }
        let cat = (e.category ?? "").lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
        let srv = (e.serviceName ?? "").lowercased()
        return cat.contains("wifi") || srv.contains("wifi") || srv.contains("ssid")
    }
    
    private var decryptedString: String { String(data: decryptedData, encoding: .utf8) ?? "" }
    
    private var lastUpdatedString: String {
        guard let e = selectedPassword else { return "" }
        let date = e.updatedAt ?? e.createdAt
        return date?.formatted(date: .abbreviated, time: .shortened) ?? ""
    }
    
    var body: some View {
        Group {
            if let entry = selectedPassword {
                ScrollView {
                    VStack(spacing: 30) {
                        headerSection(entry)
                        credentialsSection(entry)
                        
                        // 2FA Display Section
                        if !isWiFiEntry {
                            twoFactorDisplaySection(entry)
                        }
                        
                        // NEW: Notes section
                        if let notes = entry.notes, !notes.isEmpty {
                            notesSection(notes)
                        }
                        
                        // NEW: Tags section
                        if !entry.safeTagArray.isEmpty {
                            tagsDisplaySection(entry)
                        }
                        
                        // NEW: Expiry warning
                        if let expiry = entry.passwordExpiry {
                            expirySection(expiry: expiry, entry: entry)
                        }
                        
                        actionsSection(entry)
                    }
                    .padding()
                }
                .scrollIndicators(.never)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "rectangle.on.rectangle.slash",
                    description: Text("Select a service to view its details.")
                )
                .padding()
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showPassword)
        .sheet(isPresented: $showAddTOTP) {
            if let entry = selectedPassword {
                AddTOTPSecretView(entry: entry)
                    .environmentObject(theme)
                    .environment(\.managedObjectContext, viewContext)
            }
        }
        .sheet(isPresented: $showRemoveTOTP) {
            if let entry = selectedPassword {
                RemoveTOTPView(entry: entry)
                    .environmentObject(theme)
                    .environment(\.managedObjectContext, viewContext)
            }
        }
        .onDisappear {
            cancelHideTask()
            wipeDecrypted()
        }
        .task(id: selectedPassword?.objectID) {
            cancelHideTask()
            showPassword = false
            wipeDecrypted()
        }
        .overlay(
            Text("Editing Mode")
                .font(.caption)
                .foregroundStyle(theme.primaryTextColor)
                .padding(6)
                .background(.thinMaterial, in: Capsule())
                .opacity(isEditing ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: isEditing),
            alignment: .topTrailing
        )
    }
    
    // MARK: - Header
    private func headerSection(_ entry: PasswordEntry) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(theme.adaptiveTileBackground)
                    .frame(width: 72, height: 72)
                    .overlay(
                        Text(entry.serviceName?.prefix(1).uppercased() ?? "?")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(theme.primaryTextColor)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(theme.isDarkBackground ? Color.white.opacity(0.1) : Color.clear, lineWidth: 1)
                    )
                
                // 2FA Badge Indicator
                if entry.hasTwoFactor {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(4)
                        .background(Circle().fill(theme.adaptiveTileBackground))
                        .offset(x: 24, y: -24)
                }
                
                // Favorite Star Indicator
                if entry.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                        .padding(4)
                        .background(Circle().fill(theme.adaptiveTileBackground))
                        .offset(x: -24, y: -24)
                }
            }
            .shadow(radius: 2)
            
            Text(entry.serviceName ?? "Unknown Service")
                .font(.title2.bold())
                .foregroundColor(theme.primaryTextColor)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 8) {
                if let cat = entry.category, !cat.isEmpty {
                    Text(cat)
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(theme.badgeBackground, in: Capsule())
                        .foregroundStyle(.white)
                }
                
                if entry.hasTwoFactor {
                    TOTPShieldBadge()
                        .environmentObject(theme)
                }
                
                if entry.isFavorite {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                        Text("Favorite")
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.yellow.opacity(0.2), in: Capsule())
                    .foregroundStyle(.yellow)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
    }
    
    // MARK: - Credentials Section
    private func credentialsSection(_ entry: PasswordEntry) -> some View {
        VStack(spacing: 16) {
            if isEditing {
                editableFieldsSection(entry)
            } else {
                readOnlyFieldsSection(entry)
            }
            
            if !lastUpdatedString.isEmpty {
                Label("Updated \(lastUpdatedString)", systemImage: "calendar.badge.clock")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryTextColor)
                    .padding(.top, 8)
            }
        }
        .padding()
        .background(theme.adaptiveTileBackground, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(theme.isDarkBackground ? Color.white.opacity(0.08) : Color.clear, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
        .frame(maxWidth: 480)
    }
    
    private func readOnlyFieldsSection(_ entry: PasswordEntry) -> some View {
        Group {
            if let user = entry.username, !user.isEmpty {
                ValueRow(icon: "person.fill", title: "Username", value: user) { copyToClipboard(user) }
                    .environmentObject(theme)
                    .onTapGesture(count: 2) { beginEdit(entry) }
            }
            if let mail = entry.lgdata, !mail.isEmpty {
                ValueRow(icon: "envelope.fill", title: "Email/Login", value: mail) { copyToClipboard(mail) }
                    .environmentObject(theme)
                    .onTapGesture(count: 2) { beginEdit(entry) }
            }
            if let site = entry.website, !site.isEmpty {
                ValueRow(icon: "globe", title: "Website", value: site) { copyToClipboard(site) }
                    .environmentObject(theme)
                    .onTapGesture(count: 2) { beginEdit(entry) }
            }
            if isWiFiEntry, let serviceName = entry.serviceName, !serviceName.isEmpty {
                ValueRow(icon: "wifi", title: "SSID", value: serviceName) { copyToClipboard(serviceName) }
                    .environmentObject(theme)
                    .onTapGesture(count: 2) { beginEdit(entry) }
            }
            if !isWiFiEntry, let ph = entry.phn, !ph.isEmpty {
                ValueRow(icon: "phone.fill", title: "Phone", value: ph) { copyToClipboard(ph) }
                    .environmentObject(theme)
                    .onTapGesture(count: 2) { beginEdit(entry) }
            }
            SecureRevealField(
                label: isWiFiEntry ? "Wi-Fi Key" : "Password",
                value: decryptedString.isEmpty ? "••••••••" : decryptedString,
                isRevealed: $showPassword,
                onReveal: { togglePasswordVisibility(for: entry) },
                onCopy: { copyPassword(for: entry) }
            )
            .environmentObject(theme)
            .onTapGesture(count: 2) { beginEdit(entry) }
        }
    }
    
    private func editableFieldsSection(_ entry: PasswordEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Service Name", text: $editableEntry.serviceName)
                .textFieldStyle(.roundedBorder)
            TextField("Username", text: $editableEntry.username)
                .textFieldStyle(.roundedBorder)
            TextField("Email/Login", text: $editableEntry.lgdata)
                .textFieldStyle(.roundedBorder)
            TextField("Phone", text: $editableEntry.phn)
                .textFieldStyle(.roundedBorder)
            TextField("Website", text: $editableEntry.website)
                .textFieldStyle(.roundedBorder)
            SecureField("Password", text: $editableEntry.password)
                .textFieldStyle(.roundedBorder)
            
            HStack(spacing: 16) {
                Button("Cancel") {
                    isEditing = false
                    editableEntry = .empty
                }
                .buttonStyle(.bordered)
                
                Button("Save") {
                    saveInlineChanges(for: entry)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.badgeBackground)
            }
            .padding(.top, 10)
        }
    }
    
    // MARK: - NEW SECTIONS
    
    @ViewBuilder
    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Notes", systemImage: "note.text")
                .font(.headline)
                .foregroundColor(theme.primaryTextColor)
            
            Text(notes)
                .font(.body)
                .foregroundColor(theme.secondaryTextColor)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(theme.isDarkBackground ? Color.white.opacity(0.05) : Color.gray.opacity(0.1))
                .cornerRadius(8)
            
            Button {
                copyToClipboard(notes)
            } label: {
                Label("Copy Notes", systemImage: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .background(theme.adaptiveTileBackground, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(theme.isDarkBackground ? Color.white.opacity(0.08) : Color.clear, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
        .frame(maxWidth: 480)
    }
    
    @ViewBuilder
    private func tagsDisplaySection(_ entry: PasswordEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Tags", systemImage: "tag.fill")
                .font(.headline)
                .foregroundColor(theme.primaryTextColor)
            
            FlowLayout(spacing: 8) {
                ForEach(entry.safeTagArray, id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(theme.badgeBackground.opacity(0.2), in: Capsule())
                        .foregroundColor(theme.primaryTextColor)
                }
            }
        }
        .padding()
        .background(theme.adaptiveTileBackground, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(theme.isDarkBackground ? Color.white.opacity(0.08) : Color.clear, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
        .frame(maxWidth: 480)
    }
    
    @ViewBuilder
    private func expirySection(expiry: Date, entry: PasswordEntry) -> some View {
        let daysUntil = entry.safeDaysUntilExpiry ?? 0
        let isExpired = entry.isSafelyExpired
        let isExpiringSoon = entry.isSafelyExpiringSoon
        
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: isExpired ? "exclamationmark.triangle.fill" : "calendar.badge.clock")
                    .foregroundColor(isExpired ? .red : (isExpiringSoon ? .orange : theme.badgeBackground))
                
                Text(isExpired ? "Password Expired" : "Password Expiry")
                    .font(.headline)
                    .foregroundColor(theme.primaryTextColor)
                
                Spacer()
            }
            
            HStack {
                if isExpired {
                    Text("Expired on")
                        .font(.subheadline)
                        .foregroundColor(theme.secondaryTextColor)
                    Text(expiry, style: .date)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.red)
                } else if isExpiringSoon {
                    Text("Expires in")
                        .font(.subheadline)
                        .foregroundColor(theme.secondaryTextColor)
                    Text("\(daysUntil) day\(daysUntil == 1 ? "" : "s")")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.orange)
                } else {
                    Text("Expires on")
                        .font(.subheadline)
                        .foregroundColor(theme.secondaryTextColor)
                    Text(expiry, style: .date)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(theme.primaryTextColor)
                }
            }
            
            if isExpired || isExpiringSoon {
                Button {
                    onEdit(entry)
                } label: {
                    Label("Update Password", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(isExpired ? .red : .orange)
                .controlSize(.small)
            }
        }
        .padding()
        .background(
            (isExpired ? Color.red : (isExpiringSoon ? Color.orange : theme.badgeBackground))
                .opacity(0.1),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    (isExpired ? Color.red : (isExpiringSoon ? Color.orange : theme.badgeBackground))
                        .opacity(0.3),
                    lineWidth: 1
                )
        )
        .frame(maxWidth: 480)
    }
    
    // MARK: - 2FA Display Section
    @ViewBuilder
    private func twoFactorDisplaySection(_ entry: PasswordEntry) -> some View {
        VStack(spacing: 16) {
            if entry.hasTwoFactor {
                // Show TOTP code with timer
                TOTPDisplayView(entry: entry)
                    .environmentObject(theme)
                    .padding()
                    .background(theme.adaptiveTileBackground, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(theme.isDarkBackground ? Color.white.opacity(0.08) : Color.clear, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
                    .frame(maxWidth: 480)
                
                // Management buttons
                HStack(spacing: 12) {
                    Button {
                        showAddTOTP = true
                    } label: {
                        Label("Update Secret", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button(role: .destructive) {
                        showRemoveTOTP = true
                    } label: {
                        Label("Remove 2FA", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                // Show add 2FA button
                Button {
                    showAddTOTP = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(theme.badgeBackground)
                        Text("Add Two-Factor Authentication")
                            .foregroundColor(theme.primaryTextColor)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(theme.adaptiveTileBackground, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(theme.badgeBackground.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5]))
                    )
                }
                .buttonStyle(.plain)
                //.frame(maxWidth: 480)
            }
        }
    }
    
    // MARK: - Action Bar
    private func actionsSection(_ entry: PasswordEntry) -> some View {
        HStack(spacing: 20) {
            Button {
                onEdit(entry)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.badgeBackground)
            .controlSize(.large)
            
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .popover(isPresented: $showDeleteConfirm) {
                deleteConfirmPopover(entry)
            }
            
            if isWiFiEntry {
                Button {
                    showWiFiQRPopover.toggle()
                } label: {
                    Label("QR Code", systemImage: "qrcode")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .popover(isPresented: $showWiFiQRPopover) {
                    wiFiQRPopover(entry: entry)
                        .padding()
                }
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - Reusable Views
    private func deleteConfirmPopover(_ entry: PasswordEntry) -> some View {
        VStack(spacing: 16) {
            Text("Delete this entry?")
                .font(.headline)
                .foregroundColor(theme.primaryTextColor)
            Text("This action cannot be undone.")
                .font(.caption)
                .foregroundStyle(theme.secondaryTextColor)
            HStack {
                Button("Delete", role: .destructive) {
                    onDelete(entry)
                    showDeleteConfirm = false
                }
                Button("Cancel", role: .cancel) {
                    showDeleteConfirm = false
                }
            }
        }
        .padding()
        .frame(width: 220)
    }
    
    struct ValueRow: View {
        @EnvironmentObject private var theme: ThemeManager
        let icon: String
        let title: String
        let value: String
        var onCopy: () -> Void
        
        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(theme.badgeBackground)
                    .frame(width: 20)
                Text(title)
                    .font(.headline)
                    .foregroundColor(theme.primaryTextColor)
                Spacer()
                Text(value)
                    .foregroundStyle(theme.primaryTextColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(theme.secondaryTextColor)
                }
                .buttonStyle(.plain)
                .help("Copy \(title.lowercased())")
            }
        }
    }
    
    struct SecureRevealField: View {
        @EnvironmentObject private var theme: ThemeManager
        let label: String
        let value: String
        @Binding var isRevealed: Bool
        var onReveal: () -> Void
        var onCopy: () -> Void
        
        var body: some View {
            HStack {
                Label(label, systemImage: "key.fill")
                    .font(.headline)
                    .foregroundStyle(theme.badgeBackground)
                Spacer()
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(isRevealed ? theme.primaryTextColor : theme.secondaryTextColor)
                    .animation(.easeInOut, value: isRevealed)
                Button(action: onReveal) {
                    Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(theme.secondaryTextColor)
                }
                .buttonStyle(.plain)
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(theme.secondaryTextColor)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Logic
    
    // MARK: - Decrypt / Wipe
    private func decryptPasswordIfNeeded(for entry: PasswordEntry) {
        guard decryptedData.isEmpty else { return }
        if let decrypted = decrypt(entry) {
            decryptedData = Data(decrypted.utf8)
        }
    }
    
    private func wipeDecrypted() {
        if !decryptedData.isEmpty {
            decryptedData.resetBytes(in: 0..<decryptedData.count)
            decryptedData = Data()
        }
    }
    
    private func cancelHideTask() {
        hidePasswordTask?.cancel()
        hidePasswordTask = nil
    }
    
    private func togglePasswordVisibility(for entry: PasswordEntry) {
        if showPassword {
            showPassword = false
            cancelHideTask()
            wipeDecrypted()
        } else {
            decryptPasswordIfNeeded(for: entry)
            showPassword = true
            cancelHideTask()
            let timeout = max(1, revealTimeout)
            hidePasswordTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000_000)
                await MainActor.run {
                    showPassword = false
                    wipeDecrypted()
                }
            }
        }
    }
    
    // MARK: - Clipboard
    private func copyPassword(for entry: PasswordEntry) {
        let secret: String? = {
            if !decryptedData.isEmpty { return decryptedString }
            return decrypt(entry)
        }()
        guard let text = secret, !text.isEmpty else { return }
        copyToClipboard(text)
        
        if decryptedData.isEmpty {
            showPassword = false
        }
    }
    
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let initialChange = pasteboard.changeCount
        
        if autoClearClipboard {
            let delay = max(1, clearDelay)
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay)) {
                if pasteboard.changeCount == initialChange {
                    pasteboard.clearContents()
                }
            }
        }
    }
    
    // MARK: - Wi‑Fi QR popover
    @ViewBuilder
    private func wiFiQRPopover(entry: PasswordEntry) -> some View {
        let ssid = entry.serviceName ?? ""
        let pass: String = {
            if !decryptedData.isEmpty { return decryptedString }
            return decrypt(entry) ?? ""
        }()
        let qrString = wifiQRString(ssid: ssid, password: pass)
        let qrImage = makeQRImage(from: qrString, dimension: 220)
        
        VStack(spacing: 12) {
            if let img = qrImage {
                Image(nsImage: img)
                    .interpolation(.none)
                    .antialiased(false)
                    .resizable()
                    .frame(width: 220, height: 220)
                    .background(Color.white)
                    .cornerRadius(8)
                    .shadow(radius: 2)
            } else {
                Text("Unable to generate QR")
                    .foregroundColor(theme.secondaryTextColor)
            }
            Text("Scan to join “\(ssid)”")
                .font(.headline)
                .foregroundColor(theme.primaryTextColor)
            HStack(spacing: 12) {
                Button {
                    if let img = qrImage {
                        copyImageToClipboard(img)
                    }
                } label: {
                    Label("Copy QR", systemImage: "doc.on.doc")
                }
                Button {
                    showWiFiQRPopover = false
                } label: {
                    Label("Close", systemImage: "xmark.circle")
                }
            }
        }
        .frame(minWidth: 260)
    }
    
    private func wifiQRString(ssid: String, password: String) -> String {
        func esc(_ s: String) -> String {
            var out = s.replacingOccurrences(of: "\\", with: "\\\\")
            out = out.replacingOccurrences(of: ";", with: "\\;")
            out = out.replacingOccurrences(of: ",", with: "\\,")
            out = out.replacingOccurrences(of: ":", with: "\\:")
            return out
        }
        if password.isEmpty {
            return "WIFI:T:nopass;S:\(esc(ssid));;"
        } else {
            return "WIFI:T:WPA;S:\(esc(ssid));P:\(esc(password));;"
        }
    }
    
    private func makeQRImage(from string: String, dimension: CGFloat) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        
        guard let outputImage = filter.outputImage else { return nil }
        
        let scaleX = dimension / outputImage.extent.size.width
        let scaleY = dimension / outputImage.extent.size.height
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        let nsImage = NSImage(size: NSSize(width: dimension, height: dimension))
        nsImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(cgImage: cgImage, size: NSSize(width: dimension, height: dimension)).draw(at: .zero, from: NSRect(x: 0, y: 0, width: dimension, height: dimension), operation: .copy, fraction: 1.0)
        nsImage.unlockFocus()
        return nsImage
    }
    
    private func copyImageToClipboard(_ image: NSImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let tiff = image.tiffRepresentation {
            pb.setData(tiff, forType: .tiff)
        }
    }
    
    private func beginEdit(_ entry: PasswordEntry) {
        editableEntry = EditablePassword(entry: entry)
        isEditing = true
    }
    
    private func saveInlineChanges(for entry: PasswordEntry) {
        let context = PersistenceController.shared.container.viewContext
        
        let passwordToUse: Data
        if !editableEntry.password.isEmpty {
            passwordToUse = Data(editableEntry.password.utf8)
        } else if let existing = decrypt(entry) {
            passwordToUse = Data(existing.utf8)
        } else {
            isEditing = false
            editableEntry = .empty
            return
        }
        
        // Convert tags array back to comma-separated string
        let tagsString = editableEntry.tags.isEmpty ? nil : editableEntry.tags.joined(separator: ",")
        
        CoreDataHelper.upsertPassword(
            entry: entry,
            serviceName: editableEntry.serviceName,
            username: editableEntry.username,
            lgdata: editableEntry.lgdata,
            countryCode: entry.countryCode ?? "",
            phn: editableEntry.phn,
            website: editableEntry.website,
            passwordData: passwordToUse,
            category: entry.category ?? "Other",
            notes: editableEntry.notes.isEmpty ? nil : editableEntry.notes,
            isFavorite: editableEntry.isFavorite,
            passwordExpiry: entry.passwordExpiry,
            tags: tagsString,
            context: context
        )
        
        isEditing = false
        editableEntry = .empty
        editableEntry.password.removeAll(keepingCapacity: false)
    }
}
*/


import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

@available(macOS 15.0, *)
@MainActor
final class EditablePassword {
    var serviceName: String = ""
    var username: String = ""
    var lgdata: String = ""
    var phn: String = ""
    var website: String = ""
    var password: String = ""
    var notes: String = ""
    var isFavorite: Bool = false
    var tags: [String] = []
    
    static var empty: EditablePassword { EditablePassword() }
    
    init(entry: PasswordEntry) {
        self.serviceName = entry.serviceName ?? ""
        self.username = entry.username ?? ""
        self.lgdata = entry.lgdata ?? ""
        self.phn = entry.phn ?? ""
        self.website = entry.website ?? ""
        self.password = ""
        
        // SAFE: Use nil-coalescing for optional fields
        self.notes = entry.notes ?? ""
        self.isFavorite = entry.isFavorite
        
        // SAFE: Use the safe tag accessor
        self.tags = entry.safeTagArray
    }
    
    init() {}
}

@available(macOS 15.0, *)
struct PasswordDetailsView: View {
    var selectedPassword: PasswordEntry?
    var decrypt: (PasswordEntry) -> SecData?
    var onEdit: (PasswordEntry) -> Void
    var onDelete: (PasswordEntry) -> Void
    
    @State private var decryptedPassword: String = ""
    @State private var decryptedData = Data()
    @State private var showPassword: Bool = false
    @State private var hidePasswordTask: Task<Void, Never>? = nil
    
    @State private var isEditing: Bool = false
    @State private var editableEntry: EditablePassword = .empty
    
    // ✅ Only keep essential AppStorage properties
    @AppStorage("clearDelay") private var clearDelay: Int = 10
    @AppStorage("RevealTimeoutSeconds") private var revealTimeout: Int = 5
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var theme: ThemeManager
    
    @State private var showWiFiQRPopover: Bool = false
    @State private var showDeleteConfirm: Bool = false
    
    // 2FA states
    @State private var showAddTOTP = false
    @State private var showRemoveTOTP = false
    
    // ✅ NEW: Visual feedback for copy operations
    @State private var justCopied: String? = nil
    
    private var isWiFiEntry: Bool {
        guard let e = selectedPassword else { return false }
        let cat = (e.category ?? "").lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
        let srv = (e.serviceName ?? "").lowercased()
        return cat.contains("wifi") || srv.contains("wifi") || srv.contains("ssid")
    }
    
    private var decryptedString: String { String(data: decryptedData, encoding: .utf8) ?? "" }
    
    private var lastUpdatedString: String {
        guard let e = selectedPassword else { return "" }
        let date = e.updatedAt ?? e.createdAt
        return date?.formatted(date: .abbreviated, time: .shortened) ?? ""
    }
    
    var body: some View {
        ZStack {
            Group {
                if let entry = selectedPassword {
                    ScrollView {
                        VStack(spacing: 30) {
                            headerSection(entry)
                            credentialsSection(entry)
                            
                            // 2FA Display Section
                            if !isWiFiEntry {
                                twoFactorDisplaySection(entry)
                            }
                            
                            // Notes section
                            if let notes = entry.notes, !notes.isEmpty {
                                notesSection(notes, entry: entry)
                            }
                            
                            // Tags section
                            if !entry.safeTagArray.isEmpty {
                                tagsDisplaySection(entry)
                            }
                            
                            // Expiry warning
                            if let expiry = entry.passwordExpiry {
                                expirySection(expiry: expiry, entry: entry)
                            }
                            
                            actionsSection(entry)
                        }
                        .padding()
                    }
                    .scrollIndicators(.never)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                    ContentUnavailableView(
                        "No Selection",
                        systemImage: "rectangle.on.rectangle.slash",
                        description: Text("Select a service to view its details.")
                    )
                    .padding()
                    .transition(.opacity)
                }
            }
            
            // ✅ Copy feedback toast
            if let copied = justCopied {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Copied \(copied)")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    .transition(.scale.combined(with: .opacity))
                    .padding(.bottom, 20)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: justCopied != nil)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showPassword)
        .sheet(isPresented: $showAddTOTP) {
            if let entry = selectedPassword {
                AddTOTPSecretView(entry: entry)
                    .environmentObject(theme)
                    .environment(\.managedObjectContext, viewContext)
            }
        }
        .sheet(isPresented: $showRemoveTOTP) {
            if let entry = selectedPassword {
                RemoveTOTPView(entry: entry)
                    .environmentObject(theme)
                    .environment(\.managedObjectContext, viewContext)
            }
        }
        .onDisappear {
            cancelHideTask()
            wipeDecrypted()
        }
        .task(id: selectedPassword?.objectID) {
            cancelHideTask()
            showPassword = false
            wipeDecrypted()
        }
        .overlay(
            Text("Editing Mode")
                .font(.caption)
                .foregroundStyle(theme.primaryTextColor)
                .padding(6)
                .background(.thinMaterial, in: Capsule())
                .opacity(isEditing ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: isEditing),
            alignment: .topTrailing
        )
    }
    
    // MARK: - Header
    private func headerSection(_ entry: PasswordEntry) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(theme.adaptiveTileBackground)
                    .frame(width: 72, height: 72)
                    .overlay(
                        Text(entry.serviceName?.prefix(1).uppercased() ?? "?")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(theme.primaryTextColor)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(theme.isDarkBackground ? Color.white.opacity(0.1) : Color.clear, lineWidth: 1)
                    )
                
                // 2FA Badge Indicator
                if entry.hasTwoFactor {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(4)
                        .background(Circle().fill(theme.adaptiveTileBackground))
                        .offset(x: 24, y: -24)
                }
                
                // Favorite Star Indicator
                if entry.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                        .padding(4)
                        .background(Circle().fill(theme.adaptiveTileBackground))
                        .offset(x: -24, y: -24)
                }
            }
            .shadow(radius: 2)
            
            Text(entry.serviceName ?? "Unknown Service")
                .font(.title2.bold())
                .foregroundColor(theme.primaryTextColor)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 8) {
                if let cat = entry.category, !cat.isEmpty {
                    Text(cat)
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(theme.badgeBackground, in: Capsule())
                        .foregroundStyle(.white)
                }
                
                if entry.hasTwoFactor {
                    TOTPShieldBadge()
                        .environmentObject(theme)
                }
                
                if entry.isFavorite {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                        Text("Favorite")
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.yellow.opacity(0.2), in: Capsule())
                    .foregroundStyle(.yellow)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
    }
    
    // MARK: - Credentials Section
    private func credentialsSection(_ entry: PasswordEntry) -> some View {
        VStack(spacing: 16) {
            if isEditing {
                editableFieldsSection(entry)
            } else {
                readOnlyFieldsSection(entry)
            }
            
            if !lastUpdatedString.isEmpty {
                Label("Updated \(lastUpdatedString)", systemImage: "calendar.badge.clock")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryTextColor)
                    .padding(.top, 8)
            }
        }
        .padding()
        .background(theme.adaptiveTileBackground, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(theme.isDarkBackground ? Color.white.opacity(0.08) : Color.clear, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
        .frame(maxWidth: 480)
    }
    
    private func readOnlyFieldsSection(_ entry: PasswordEntry) -> some View {
        Group {
            if let user = entry.username, !user.isEmpty {
                ValueRow(icon: "person.fill", title: "Username", value: user) {
                    copyWithFeedback(user, fieldName: "Username", entryID: entry.id ?? UUID())
                }
                .environmentObject(theme)
                .onTapGesture(count: 2) { beginEdit(entry) }
            }
            
            if let mail = entry.lgdata, !mail.isEmpty {
                ValueRow(icon: "envelope.fill", title: "Email/Login", value: mail) {
                    copyWithFeedback(mail, fieldName: "Email", entryID: entry.id ?? UUID())
                }
                .environmentObject(theme)
                .onTapGesture(count: 2) { beginEdit(entry) }
            }
            
            if let site = entry.website, !site.isEmpty {
                ValueRow(icon: "globe", title: "Website", value: site) {
                    copyWithFeedback(site, fieldName: "Website", entryID: entry.id ?? UUID())
                }
                .environmentObject(theme)
                .onTapGesture(count: 2) { beginEdit(entry) }
            }
            
            if isWiFiEntry, let serviceName = entry.serviceName, !serviceName.isEmpty {
                ValueRow(icon: "wifi", title: "SSID", value: serviceName) {
                    copyWithFeedback(serviceName, fieldName: "SSID", entryID: entry.id ?? UUID())
                }
                .environmentObject(theme)
                .onTapGesture(count: 2) { beginEdit(entry) }
            }
            
            if !isWiFiEntry, let ph = entry.phn, !ph.isEmpty {
                ValueRow(icon: "phone.fill", title: "Phone", value: ph) {
                    copyWithFeedback(ph, fieldName: "Phone", entryID: entry.id ?? UUID())
                }
                .environmentObject(theme)
                .onTapGesture(count: 2) { beginEdit(entry) }
            }
            
            SecureRevealField(
                label: isWiFiEntry ? "Wi-Fi Key" : "Password",
                value: decryptedString.isEmpty ? "••••••••" : decryptedString,
                isRevealed: $showPassword,
                onReveal: { togglePasswordVisibility(for: entry) },
                onCopy: {
                    copyWithFeedback(decryptedString, fieldName: "Password", entryID: entry.id ?? UUID())
                }
            )
            .environmentObject(theme)
            .onTapGesture(count: 2) { beginEdit(entry) }
        }
    }
    
    private func editableFieldsSection(_ entry: PasswordEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Service Name", text: $editableEntry.serviceName)
                .textFieldStyle(.roundedBorder)
            TextField("Username", text: $editableEntry.username)
                .textFieldStyle(.roundedBorder)
            TextField("Email/Login", text: $editableEntry.lgdata)
                .textFieldStyle(.roundedBorder)
            TextField("Phone", text: $editableEntry.phn)
                .textFieldStyle(.roundedBorder)
            TextField("Website", text: $editableEntry.website)
                .textFieldStyle(.roundedBorder)
            SecureField("Password", text: $editableEntry.password)
                .textFieldStyle(.roundedBorder)
            
            HStack(spacing: 16) {
                Button("Cancel") {
                    isEditing = false
                    editableEntry = .empty
                }
                .buttonStyle(.bordered)
                
                Button("Save") {
                    saveInlineChanges(for: entry)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.badgeBackground)
            }
            .padding(.top, 10)
        }
    }
    
    // MARK: - NEW SECTIONS
    
    @ViewBuilder
    private func notesSection(_ notes: String, entry: PasswordEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Notes", systemImage: "note.text")
                .font(.headline)
                .foregroundColor(theme.primaryTextColor)
            
            Text(notes)
                .font(.body)
                .foregroundColor(theme.secondaryTextColor)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(theme.isDarkBackground ? Color.white.opacity(0.05) : Color.gray.opacity(0.1))
                .cornerRadius(8)
            
            Button {
                copyWithFeedback(notes, fieldName: "Notes", entryID: entry.id ?? UUID())
            } label: {
                Label("Copy Notes", systemImage: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .background(theme.adaptiveTileBackground, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(theme.isDarkBackground ? Color.white.opacity(0.08) : Color.clear, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
        .frame(maxWidth: 480)
    }
    
    @ViewBuilder
    private func tagsDisplaySection(_ entry: PasswordEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Tags", systemImage: "tag.fill")
                .font(.headline)
                .foregroundColor(theme.primaryTextColor)
            
            FlowLayout(spacing: 8) {
                ForEach(entry.safeTagArray, id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(theme.badgeBackground.opacity(0.2), in: Capsule())
                        .foregroundColor(theme.primaryTextColor)
                }
            }
        }
        .padding()
        .background(theme.adaptiveTileBackground, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(theme.isDarkBackground ? Color.white.opacity(0.08) : Color.clear, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
        .frame(maxWidth: 480)
    }
    
    @ViewBuilder
    private func expirySection(expiry: Date, entry: PasswordEntry) -> some View {
        let daysUntil = entry.safeDaysUntilExpiry ?? 0
        let isExpired = entry.isSafelyExpired
        let isExpiringSoon = entry.isSafelyExpiringSoon
        
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: isExpired ? "exclamationmark.triangle.fill" : "calendar.badge.clock")
                    .foregroundColor(isExpired ? .red : (isExpiringSoon ? .orange : theme.badgeBackground))
                
                Text(isExpired ? "Password Expired" : "Password Expiry")
                    .font(.headline)
                    .foregroundColor(theme.primaryTextColor)
                
                Spacer()
            }
            
            HStack {
                if isExpired {
                    Text("Expired on")
                        .font(.subheadline)
                        .foregroundColor(theme.secondaryTextColor)
                    Text(expiry, style: .date)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.red)
                } else if isExpiringSoon {
                    Text("Expires in")
                        .font(.subheadline)
                        .foregroundColor(theme.secondaryTextColor)
                    Text("\(daysUntil) day\(daysUntil == 1 ? "" : "s")")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.orange)
                } else {
                    Text("Expires on")
                        .font(.subheadline)
                        .foregroundColor(theme.secondaryTextColor)
                    Text(expiry, style: .date)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(theme.primaryTextColor)
                }
            }
            
            if isExpired || isExpiringSoon {
                Button {
                    onEdit(entry)
                } label: {
                    Label("Update Password", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(isExpired ? .red : .orange)
                .controlSize(.small)
            }
        }
        .padding()
        .background(
            (isExpired ? Color.red : (isExpiringSoon ? Color.orange : theme.badgeBackground))
                .opacity(0.1),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    (isExpired ? Color.red : (isExpiringSoon ? Color.orange : theme.badgeBackground))
                        .opacity(0.3),
                    lineWidth: 1
                )
        )
        .frame(maxWidth: 480)
    }
    
    // MARK: - 2FA Display Section
    @ViewBuilder
    private func twoFactorDisplaySection(_ entry: PasswordEntry) -> some View {
        VStack(spacing: 16) {
            if entry.hasTwoFactor {
                // Show TOTP code with timer
                TOTPDisplayView(entry: entry)
                    .environmentObject(theme)
                    .padding()
                    .background(theme.adaptiveTileBackground, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(theme.isDarkBackground ? Color.white.opacity(0.08) : Color.clear, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
                    .frame(maxWidth: 480)
                
                // Management buttons
                HStack(spacing: 12) {
                    Button {
                        showAddTOTP = true
                    } label: {
                        Label("Update Secret", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button(role: .destructive) {
                        showRemoveTOTP = true
                    } label: {
                        Label("Remove 2FA", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                // Show add 2FA button
                Button {
                    showAddTOTP = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(theme.badgeBackground)
                        Text("Add Two-Factor Authentication")
                            .foregroundColor(theme.primaryTextColor)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(theme.adaptiveTileBackground, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(theme.badgeBackground.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5]))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Action Bar
    private func actionsSection(_ entry: PasswordEntry) -> some View {
        HStack(spacing: 20) {
            Button {
                onEdit(entry)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.badgeBackground)
            .controlSize(.large)
            
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .popover(isPresented: $showDeleteConfirm) {
                deleteConfirmPopover(entry)
            }
            
            if isWiFiEntry {
                Button {
                    showWiFiQRPopover.toggle()
                } label: {
                    Label("QR Code", systemImage: "qrcode")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .popover(isPresented: $showWiFiQRPopover) {
                    wiFiQRPopover(entry: entry)
                        .padding()
                }
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - Reusable Views
    private func deleteConfirmPopover(_ entry: PasswordEntry) -> some View {
        VStack(spacing: 16) {
            Text("Delete this entry?")
                .font(.headline)
                .foregroundColor(theme.primaryTextColor)
            Text("This action cannot be undone.")
                .font(.caption)
                .foregroundStyle(theme.secondaryTextColor)
            HStack {
                Button("Delete", role: .destructive) {
                    onDelete(entry)
                    showDeleteConfirm = false
                }
                Button("Cancel", role: .cancel) {
                    showDeleteConfirm = false
                }
            }
        }
        .padding()
        .frame(width: 220)
    }
    
    struct ValueRow: View {
        @EnvironmentObject private var theme: ThemeManager
        let icon: String
        let title: String
        let value: String
        var onCopy: () -> Void
        
        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(theme.badgeBackground)
                    .frame(width: 20)
                Text(title)
                    .font(.headline)
                    .foregroundColor(theme.primaryTextColor)
                Spacer()
                Text(value)
                    .foregroundStyle(theme.primaryTextColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(theme.secondaryTextColor)
                }
                .buttonStyle(.plain)
                .help("Copy \(title.lowercased())")
            }
        }
    }
    
    struct SecureRevealField: View {
        @EnvironmentObject private var theme: ThemeManager
        let label: String
        let value: String
        @Binding var isRevealed: Bool
        var onReveal: () -> Void
        var onCopy: () -> Void
        
        var body: some View {
            HStack {
                Label(label, systemImage: "key.fill")
                    .font(.headline)
                    .foregroundStyle(theme.badgeBackground)
                Spacer()
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(isRevealed ? theme.primaryTextColor : theme.secondaryTextColor)
                    .animation(.easeInOut, value: isRevealed)
                Button(action: onReveal) {
                    Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(theme.secondaryTextColor)
                }
                .buttonStyle(.plain)
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(theme.secondaryTextColor)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - ✅ SECURE CLIPBOARD OPERATIONS
    
    /// Copies text to clipboard with SecureClipboard and shows visual feedback
    private func copyWithFeedback(_ text: String, fieldName: String, entryID: UUID) {
        Task { @MainActor in
            // Copy using SecureClipboard
            await SecureClipboard.shared.copy(
                text: text,
                entryID: entryID,
                clearAfter: TimeInterval(max(1, clearDelay))
            )
            
            // Show feedback
            justCopied = fieldName
            
            // Clear feedback after 2 seconds
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            justCopied = nil
        }
    }
    
    // MARK: - Logic
    
    // MARK: - Decrypt / Wipe
    private func decryptPasswordIfNeeded(for entry: PasswordEntry) {
        guard decryptedData.isEmpty else { return }
        if let secData = decrypt(entry) {
            defer { secData.clear() }  // ✅ Always clear SecData
            
            // Extract Data from SecData
            decryptedData = secData.withUnsafeBytes { ptr in
                guard let base = ptr.baseAddress else { return Data() }
                return Data(bytes: base, count: ptr.count)
            }
        }
    }
    
    private func wipeDecrypted() {
        if !decryptedData.isEmpty {
            decryptedData.resetBytes(in: 0..<decryptedData.count)
            decryptedData = Data()
        }
    }
    
    private func cancelHideTask() {
        hidePasswordTask?.cancel()
        hidePasswordTask = nil
    }
    
    private func togglePasswordVisibility(for entry: PasswordEntry) {
        if showPassword {
            showPassword = false
            cancelHideTask()
            wipeDecrypted()
        } else {
            decryptPasswordIfNeeded(for: entry)
            showPassword = true
            cancelHideTask()
            let timeout = max(1, revealTimeout)
            hidePasswordTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000_000)
                await MainActor.run {
                    showPassword = false
                    wipeDecrypted()
                }
            }
        }
    }
    
    // MARK: - Wi‑Fi QR popover
    @ViewBuilder
    private func wiFiQRPopover(entry: PasswordEntry) -> some View {
        let ssid = entry.serviceName ?? ""
        // If decrypt returns SecData?:
        let pass: String = {
            if !decryptedData.isEmpty { return decryptedString }
            
            guard let secData = decrypt(entry) else { return "" }
            defer { secData.clear() }
            
            return secData.withUnsafeBytes { ptr in
                guard let base = ptr.baseAddress else { return "" }
                let data = Data(bytes: base, count: ptr.count)
                return String(data: data, encoding: .utf8) ?? ""
            }
        }()
        let qrString = wifiQRString(ssid: ssid, password: pass)
        let qrImage = makeQRImage(from: qrString, dimension: 220)
        
        VStack(spacing: 12) {
            if let img = qrImage {
                Image(nsImage: img)
                    .interpolation(.none)
                    .antialiased(false)
                    .resizable()
                    .frame(width: 220, height: 220)
                    .background(Color.white)
                    .cornerRadius(8)
                    .shadow(radius: 2)
            } else {
                Text("Unable to generate QR")
                    .foregroundColor(theme.secondaryTextColor)
            }
            Text("Scan to join “\(ssid)”")
                .font(.headline)
                .foregroundColor(theme.primaryTextColor)
            HStack(spacing: 12) {
                Button {
                    if let img = qrImage {
                        copyImageToClipboard(img)
                    }
                } label: {
                    Label("Copy QR", systemImage: "doc.on.doc")
                }
                Button {
                    showWiFiQRPopover = false
                } label: {
                    Label("Close", systemImage: "xmark.circle")
                }
            }
        }
        .frame(minWidth: 260)
    }
    
    private func wifiQRString(ssid: String, password: String) -> String {
        func esc(_ s: String) -> String {
            var out = s.replacingOccurrences(of: "\\", with: "\\\\")
            out = out.replacingOccurrences(of: ";", with: "\\;")
            out = out.replacingOccurrences(of: ",", with: "\\,")
            out = out.replacingOccurrences(of: ":", with: "\\:")
            return out
        }
        if password.isEmpty {
            return "WIFI:T:nopass;S:\(esc(ssid));;"
        } else {
            return "WIFI:T:WPA;S:\(esc(ssid));P:\(esc(password));;"
        }
    }
    
    private func makeQRImage(from string: String, dimension: CGFloat) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        
        guard let outputImage = filter.outputImage else { return nil }
        
        let scaleX = dimension / outputImage.extent.size.width
        let scaleY = dimension / outputImage.extent.size.height
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        let nsImage = NSImage(size: NSSize(width: dimension, height: dimension))
        nsImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(cgImage: cgImage, size: NSSize(width: dimension, height: dimension)).draw(at: .zero, from: NSRect(x: 0, y: 0, width: dimension, height: dimension), operation: .copy, fraction: 1.0)
        nsImage.unlockFocus()
        return nsImage
    }
    
    private func copyImageToClipboard(_ image: NSImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let tiff = image.tiffRepresentation {
            pb.setData(tiff, forType: .tiff)
        }
    }
    
    private func beginEdit(_ entry: PasswordEntry) {
        editableEntry = EditablePassword(entry: entry)
        isEditing = true
    }
    
    private func saveInlineChanges(for entry: PasswordEntry) {
        let context = PersistenceController.shared.container.viewContext
        
        // Get password data
        let passwordToUse: Data
        
        if !editableEntry.password.isEmpty {
            // User edited the password - use the new one
            passwordToUse = Data(editableEntry.password.utf8)
        } else if let secData = decrypt(entry) {
            // No edit - use existing password
            defer { secData.clear() }
            passwordToUse = secData.withUnsafeBytes { ptr in
                guard let base = ptr.baseAddress else { return Data() }
                return Data(bytes: base, count: ptr.count)
            }
            
            // Also cache for display if needed
            decryptedData = passwordToUse
        } else {
            // Failed to decrypt - abort
            print("❌ Failed to get password data")
            isEditing = false
            editableEntry = .empty
            return
        }
        
        // Convert tags array back to comma-separated string
        let tagsString = editableEntry.tags.isEmpty ? nil : editableEntry.tags.joined(separator: ",")
        
        CoreDataHelper.upsertPassword(
            entry: entry,
            serviceName: editableEntry.serviceName,
            username: editableEntry.username,
            lgdata: editableEntry.lgdata,
            countryCode: entry.countryCode ?? "",
            phn: editableEntry.phn,
            website: editableEntry.website,
            passwordData: passwordToUse,  // ✅ Now always initialized
            category: entry.category ?? "Other",
            notes: editableEntry.notes.isEmpty ? nil : editableEntry.notes,
            isFavorite: editableEntry.isFavorite,
            passwordExpiry: entry.passwordExpiry,
            tags: tagsString,
            context: context
        )
        
        isEditing = false
        editableEntry = .empty
        
        // Securely clear password string
        editableEntry.password.removeAll(keepingCapacity: false)
    }
}
