/*import SwiftUI

@available(macOS 15.0, *)
@MainActor
struct BackupView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var masterPassword = ""
    @State private var exportPassword = ""
    @State private var confirmExportPassword = ""
    @State private var useExportPassword = true
    @State private var decryptBeforeExport = false
    @State private var importPassword = ""
    @State private var importMasterPassword = ""
    @State private var replaceExisting = false
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var isProcessing = false
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "externaldrive.fill.badge.checkmark")
                    .font(.title)
                    .foregroundColor(.accentColor)
                Text("Backup & Restore")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Tab Picker
            Picker("", selection: $selectedTab) {
                Label("Export", systemImage: "square.and.arrow.up").tag(0)
                Label("Import", systemImage: "square.and.arrow.down").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Content
            TabView(selection: $selectedTab) {
                exportView
                    .tag(0)
                
                importView
                    .tag(1)
            }
            .tabViewStyle(.automatic)
        }
        .frame(width: 600, height: 550)
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }
    
    // MARK: - Export View
    
    private var exportView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                // Master Password Section
                GroupBox(label: Label("Authentication Required", systemImage: "lock.shield.fill")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Enter your master password to decrypt and export data")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        SecureField("Master Password", text: $masterPassword)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.vertical, 8)
                }
                
                // Export Options
                GroupBox(label: Label("Export Options", systemImage: "gear")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Protect backup with password", isOn: $useExportPassword)
                            .toggleStyle(.switch)
                        
                        if useExportPassword {
                            VStack(alignment: .leading, spacing: 8) {
                                SecureField("Backup Password", text: $exportPassword)
                                    .textFieldStyle(.roundedBorder)
                                
                                SecureField("Confirm Backup Password", text: $confirmExportPassword)
                                    .textFieldStyle(.roundedBorder)
                                
                                if !exportPassword.isEmpty && exportPassword != confirmExportPassword {
                                    Label("Passwords do not match", systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                                
                                Text("💡 This password will be required when importing this backup")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle("⚠️ Export without encryption (plaintext)", isOn: $decryptBeforeExport)
                                    .toggleStyle(.switch)
                                    .foregroundColor(decryptBeforeExport ? .orange : .primary)
                                
                                if decryptBeforeExport {
                                    HStack(spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                        Text("Warning: Passwords will be stored in plain text! Only use for emergency recovery.")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                    .padding(8)
                                    .background(Color.orange.opacity(0.1))
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // Info
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("What's included in the backup:", systemImage: "info.circle.fill")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("• All password entries with notes")
                            Text("• All folders and categories")
                            Text("• Metadata and timestamps")
                            Text("• Folder organization")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                Spacer()
                
                // Export Button
                Button {
                    performExport()
                } label: {
                    HStack {
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(0.8)
                                .padding(.trailing, 4)
                        }
                        Image(systemName: "square.and.arrow.up.fill")
                        Text(isProcessing ? "Exporting..." : "Export Backup")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isProcessing || masterPassword.isEmpty || (useExportPassword && (exportPassword.isEmpty || exportPassword != confirmExportPassword)))
            }
            .padding()
        }
    }
    
    // MARK: - Import View
    
    private var importView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                // Master Password Section
                GroupBox(label: Label("Authentication Required", systemImage: "lock.shield.fill")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Enter your master password to decrypt and import data")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        SecureField("Master Password", text: $importMasterPassword)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.vertical, 8)
                }
                
                // Backup Password Section
                GroupBox(label: Label("Backup Password", systemImage: "key.fill")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("If your backup is password-protected, enter the password")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        SecureField("Backup Password (if protected)", text: $importPassword)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.vertical, 8)
                }
                
                // Import Options
                GroupBox(label: Label("Import Options", systemImage: "gear")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Replace all existing data", isOn: $replaceExisting)
                            .toggleStyle(.switch)
                        
                        if replaceExisting {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text("This will permanently delete all current passwords and folders!")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            .padding(8)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
                        } else {
                            Text("Backup data will be merged with existing entries")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Spacer()
                
                // Import Button
                Button {
                    selectAndImport()
                } label: {
                    HStack {
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(0.8)
                                .padding(.trailing, 4)
                        }
                        Image(systemName: "square.and.arrow.down.fill")
                        Text(isProcessing ? "Importing..." : "Select Backup File")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isProcessing || importMasterPassword.isEmpty)
            }
            .padding()
        }
    }
    
    // MARK: - Export Logic
    @MainActor
    private func performExport() {
        isProcessing = true
        
        Task { @MainActor in
            defer { isProcessing = false }
            
            do {
                let exportPwd: String? = useExportPassword
                    ? (exportPassword.isEmpty ? nil : exportPassword)
                    : nil
                
                let backupData = try await BackupManager.exportBackup(
                    context: viewContext,
                    masterPassword: masterPassword,
                    exportPassword: exportPwd,
                    decryptBeforeExport: !useExportPassword && decryptBeforeExport
                )
                
                saveBackupFile(data: backupData)
                
            } catch {
                alertTitle = "Export Failed"
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
    }
    
    private func saveBackupFile(data: Data) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "passwords-backup-\(dateString()).json"
        panel.message = "Choose where to save your encrypted backup"
        panel.prompt = "Save Backup"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try data.write(to: url, options: [.atomic, .completeFileProtection])
                    alertTitle = "✅ Export Successful"
                    alertMessage = "Backup saved successfully!\n\nFile: \(url.lastPathComponent)\nSize: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))"
                    showAlert = true
                    
                    // Clear passwords
                    clearExportForm()
                } catch {
                    alertTitle = "Save Failed"
                    alertMessage = "Failed to save backup file: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }
    
    // MARK: - Import Logic
    
    private func selectAndImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select your encrypted backup file"
        panel.prompt = "Import"
        
        panel.begin { response in
            if response == .OK, let url = panel.urls.first {
                performImport(from: url)
            }
        }
    }
    
    private func performImport(from url: URL) {
        isProcessing = true

        Task {
            do {
                let data = try Data(contentsOf: url)

                let pwd = importPassword.isEmpty ? nil : importPassword

                let (entries, folders) = try await BackupManager.importBackup(
                    backupData: data,
                    masterPassword: importMasterPassword,
                    importPassword: pwd,
                    context: viewContext,
                    replaceExisting: replaceExisting
                )

                await MainActor.run {
                    alertTitle = "✅ Import Successful"
                    alertMessage = """
                    Backup restored successfully!

                    📁 Folders imported: \(folders)
                    🔑 Passwords imported: \(entries)

                    File: \(url.lastPathComponent)
                    """
                    showAlert = true
                    isProcessing = false

                    clearImportForm()
                }

            } catch {
                await MainActor.run {
                    alertTitle = "Import Failed"
                    alertMessage = error.localizedDescription
                    showAlert = true
                    isProcessing = false
                }
            }
        }
    }

    
    // MARK: - Helper Functions
    
    private func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }
    
    private func clearExportForm() {
        masterPassword = ""
        exportPassword = ""
        confirmExportPassword = ""
    }
    
    private func clearImportForm() {
        importMasterPassword = ""
        importPassword = ""
        replaceExisting = false
    }
}

// MARK: - Window Hosting for macOS

@available(macOS 15.0, *)
struct BackupWindow: NSViewRepresentable {
    @Environment(\.managedObjectContext) private var viewContext
    
    func makeNSView(context: Context) -> NSView {
        return NSView()
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
    
    static func open(context: NSManagedObjectContext) {
        let backupView = BackupView()
            .environment(\.managedObjectContext, context)
        
        let hostingController = NSHostingController(rootView: backupView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Backup & Restore"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 600, height: 550))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        
        // Make window stay on top temporarily
        window.level = .floating
        
        // Store window reference to prevent deallocation
        objc_setAssociatedObject(
            hostingController,
            "backupWindow",
            window,
            .OBJC_ASSOCIATION_RETAIN
        )
    }
}
*/

import SwiftUI
import AppKit
import CoreData

// MARK: - Professional Backup Window (macOS 15+)
@available(macOS 15.0, *)
struct BackupWindow: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var viewModel = BackupViewModel()
    
    var body: some View {
        BackupContentView(viewModel: viewModel)
            .environment(\.managedObjectContext, viewContext)
            .frame(width: 680, height: 620)
            .preferredColorScheme(.dark)
            .background(WindowBackground())
            .onAppear { viewModel.setup(context: viewContext) }
    }
}

// MARK: - Real Window Controller (prevents deallocation)
@available(macOS 15.0, *)
final class BackupWindowController: NSWindowController {
    static var shared: BackupWindowController?
    
    convenience init(context: NSManagedObjectContext) {
        let content = BackupWindow()
            .environment(\.managedObjectContext, context)
        
        let hosting = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hosting)
        
        window.title = "Backup & Restore"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titlebarSeparatorStyle = .line
        window.backingType = .buffered
        window.setContentSize(NSSize(width: 680, height: 620))
        window.minSize = NSSize(width: 620, height: 560)
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        
        self.init(window: window)
        BackupWindowController.shared = self
    }
    
    static func open(context: NSManagedObjectContext) {
        if shared?.window?.isVisible == true { return }
        let controller = BackupWindowController(context: context)
        controller.showWindow(nil)
    }
}

// MARK: - Main Content View
@available(macOS 15.0, *)
struct BackupContentView: View {
    @ObservedObject var viewModel: BackupViewModel
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Custom Titlebar
                HStack {
                    Image(systemName: "externaldrive.fill.badge.checkmark")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    Text("Backup & Restore")
                        .font(.title2).bold()
                    Spacer()
                    Button("Help") { viewModel.showHelp() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(.ultraThickMaterial)
                
                Divider()
                
                // Tab Content
                TabView(selection: $viewModel.selectedTab) {
                    ExportTab(viewModel: viewModel)
                        .tag(0)
                        .tabItem { Label("Export", systemImage: "square.and.arrow.up.fill") }
                    
                    ImportTab(viewModel: viewModel)
                        .tag(1)
                        .tabItem { Label("Import", systemImage: "square.and.arrow.down.fill") }
                }
                .padding(.top)
            }
            .alert(viewModel.alertTitle, isPresented: $viewModel.showAlert) {
                Button("OK") { viewModel.alertAction?() }
                if viewModel.showDontShowAgain {
                    Button("Don't Show Again") { viewModel.dontShowAgain() }
                }
            } message: {
                Text(viewModel.alertMessage)
            }
            .sheet(isPresented: $viewModel.showHelpSheet) {
                HelpSheet()
            }
        }
    }
}

// MARK: - Export Tab
@available(macOS 15.0, *)
struct ExportTab: View {
    @ObservedObject var viewModel: BackupViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Master Password
                SecuritySection(title: "Master Password Required", icon: "lock.shield.fill") {
                    SecureField("Enter your master password", text: $viewModel.masterPassword)
                        .textContentType(.password)
                        .frame(maxWidth: 400)
                } description: {
                    Text("Required to decrypt your vault before export")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // Export Protection Options
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle("Protect backup with additional password", isOn: $viewModel.useExportPassword)
                            .toggleStyle(.switch)
                        
                        if viewModel.useExportPassword {
                            VStack(spacing: 12) {
                                SecureField("Backup Password", text: $viewModel.exportPassword)
                                    .textContentType(.newPassword)
                                
                                SecureField("Confirm Password", text: $viewModel.confirmExportPassword)
                                    .textContentType(.newPassword)
                                
                                if viewModel.passwordsMatch == false {
                                    Label("Passwords do not match", systemImage: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                        .font(.caption)
                                }
                            }
                            .frame(maxWidth: 400)
                        } else {
                            Toggle("Export as plaintext (emergency only)", isOn: $viewModel.decryptBeforeExport)
                                .toggleStyle(.switch)
                                .foregroundStyle(viewModel.decryptBeforeExport ? .orange : .primary)
                            
                            if viewModel.decryptBeforeExport {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                    Text("Your passwords will be stored in plain text!")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                                .padding(10)
                                .background(.orange.opacity(0.15))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding()
                } label: {
                    Label("Backup Protection", systemImage: "shield.lefthalf.filled")
                }
                
                // Export Button
                Button {
                    viewModel.performExport()
                } label: {
                    Group {
                        if viewModel.isProcessing {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Exporting...")
                            }
                        } else {
                            Label("Export Backup", systemImage: "square.and.arrow.up.fill")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: 400)
                .disabled(viewModel.exportDisabled)
            }
            .padding(32)
        }
    }
}

// MARK: - Import Tab
@available(macOS 15.0, *)
struct ImportTab: View {
    @ObservedObject var viewModel: BackupViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                SecuritySection(title: "Master Password", icon: "lock.shield.fill") {
                    SecureField("Enter your master password", text: $viewModel.importMasterPassword)
                        .textContentType(.password)
                        .frame(maxWidth: 400)
                } description: {
                    Text("Required to encrypt imported data with your vault key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                SecuritySection(title: "Backup Password (if protected)", icon: "key.fill") {
                    SecureField("Enter backup password", text: $viewModel.importPassword)
                        .textContentType(.password)
                        .frame(maxWidth: 400)
                } description: {
                    Text("Leave empty if backup is unencrypted")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Replace all existing data", isOn: $viewModel.replaceExisting)
                            .toggleStyle(.switch)
                        
                        if viewModel.replaceExisting {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text("This will permanently delete everything in your current vault!")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            .padding(10)
                            .background(.red.opacity(0.15))
                            .cornerRadius(8)
                        }
                    }
                    .padding()
                } label: {
                    Label("Import Mode", systemImage: "gearshape.2.fill")
                }
                
                Button {
                    viewModel.selectAndImport()
                } label: {
                    Group {
                        if viewModel.isProcessing {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Importing...")
                            }
                        } else {
                            Label("Select Backup File", systemImage: "folder.badge.plus")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: 400)
                .disabled(viewModel.importDisabled)
            }
            .padding(32)
        }
    }
}

// MARK: - Help Sheet
@available(macOS 15.0, *)
struct HelpSheet: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Image(systemName: "questionmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.blue)
                Text("Backup & Restore Help")
                    .font(.title2)
                    .bold()
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HelpSection(
                        icon: "square.and.arrow.up.fill",
                        title: "Export Backup",
                        content: """
                        • Master password is required to decrypt your vault
                        • Add backup password for extra security (recommended)
                        • Plaintext export is NOT recommended unless necessary
                        • Includes all passwords, folders, notes, tags, and 2FA secrets
                        """
                    )
                    
                    HelpSection(
                        icon: "square.and.arrow.down.fill",
                        title: "Import Backup",
                        content: """
                        • Master password re-encrypts data with your vault key
                        • Backup password needed only for protected backups
                        • "Replace" mode deletes all existing data first
                        • "Merge" mode (default) adds to existing data
                        """
                    )
                    
                    HelpSection(
                        icon: "shield.checkmark.fill",
                        title: "Security Notes",
                        content: """
                        • Backups are encrypted by default
                        • Use strong unique passwords for backup protection
                        • Store backups in secure locations
                        • Plaintext backups should be deleted after use
                        """
                    )
                    
                    HelpSection(
                        icon: "exclamationmark.triangle.fill",
                        title: "What's Included",
                        content: """
                        ✓ All passwords and usernames
                        ✓ Folders and organization
                        ✓ Notes and custom fields
                        ✓ Tags and favorites
                        ✓ 2FA/TOTP secrets
                        ✓ Password expiry dates
                        ✓ Creation and modification timestamps
                        """
                    )
                }
                .padding()
            }
        }
        .frame(width: 500, height: 600)
    }
}

@available(macOS 15.0, *)
struct HelpSection: View {
    let icon: String
    let title: String
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
                Text(title)
                    .font(.headline)
            }
            Text(content)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Reusable Security Section
@available(macOS 15.0, *)
struct SecuritySection<Content: View, Description: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    @ViewBuilder let description: Description
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content, @ViewBuilder description: () -> Description = { EmptyView() }) {
        self.title = title
        self.icon = icon
        self.content = content()
        self.description = description()
    }
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(.blue)
                    Text(title)
                        .font(.headline)
                }
                content
                description
            }
            .padding()
        }
    }
}

// MARK: - Background Fix for Window
@available(macOS 15.0, *)
struct WindowBackground: View {
    var body: some View {
        EffectView(material: .sidebar, blendingMode: .behindWindow)
    }
}

@available(macOS 15.0, *)
struct EffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - ViewModel with Complete Implementation
@available(macOS 15.0, *)
@MainActor
final class BackupViewModel: ObservableObject {
    @Published var selectedTab = 0
    @Published var masterPassword = ""
    @Published var exportPassword = ""
    @Published var confirmExportPassword = ""
    @Published var useExportPassword = true
    @Published var decryptBeforeExport = false
    @Published var importMasterPassword = ""
    @Published var importPassword = ""
    @Published var replaceExisting = false
    
    @Published var isProcessing = false
    @Published var showAlert = false
    @Published var alertTitle = ""
    @Published var alertMessage = ""
    @Published var alertAction: (() -> Void)?
    @Published var showDontShowAgain = false
    @Published var showHelpSheet = false
    
    private weak var context: NSManagedObjectContext?
    
    // UserDefaults keys
    private let dontShowPlaintextWarningKey = "BackupDontShowPlaintextWarning"
    
    func setup(context: NSManagedObjectContext) {
        self.context = context
    }
    
    var passwordsMatch: Bool? {
        guard !exportPassword.isEmpty else { return nil }
        return exportPassword == confirmExportPassword
    }
    
    var exportDisabled: Bool {
        isProcessing ||
        masterPassword.isEmpty ||
        (useExportPassword && (exportPassword.isEmpty || passwordsMatch == false))
    }
    
    var importDisabled: Bool {
        isProcessing || importMasterPassword.isEmpty
    }
    
    // MARK: - Export Implementation
    
    func performExport() {
        guard context != nil else { return }
        
        // Show warning for plaintext export
        if decryptBeforeExport && !UserDefaults.standard.bool(forKey: dontShowPlaintextWarningKey) {
            alertTitle = "⚠️ Plaintext Export Warning"
            alertMessage = "This will save your passwords without encryption. Anyone with access to the file can read them. Are you sure?"
            showDontShowAgain = true
            alertAction = { [weak self] in
                self?.continueExport()
            }
            showAlert = true
            return
        }
        
        continueExport()
    }
    
    private func continueExport() {
        guard let context = context else { return }
        
        isProcessing = true
        
        Task {
            do {
                let finalExportPassword = useExportPassword ? exportPassword : nil
                
                let backupData = try await BackupManager.exportBackup(
                    context: context,
                    masterPassword: masterPassword,
                    exportPassword: finalExportPassword,
                    decryptBeforeExport: decryptBeforeExport
                )
                
                await MainActor.run {
                    saveBackupFile(data: backupData)
                }
                
            } catch {
                await MainActor.run {
                    isProcessing = false
                    alertTitle = "Export Failed"
                    alertMessage = error.localizedDescription
                    showAlert = true
                    showDontShowAgain = false
                }
            }
        }
    }
    
    private func saveBackupFile(data: Data) {
        let savePanel = NSSavePanel()
        savePanel.title = "Save Backup"
        savePanel.nameFieldStringValue = "passwords-backup-\(formattedDate()).json"
        savePanel.allowedContentTypes = [.json]
        savePanel.canCreateDirectories = true
        savePanel.level = .modalPanel
        
        savePanel.begin { [weak self] response in
            guard let self = self else { return }
            
            self.isProcessing = false
            
            if response == .OK, let url = savePanel.url {
                do {
                    try data.write(to: url)
                    
                    self.alertTitle = "✅ Backup Successful"
                    self.alertMessage = "Your backup has been saved to:\n\(url.path)"
                    self.showAlert = true
                    self.showDontShowAgain = false
                    
                    // Clear passwords
                    self.masterPassword = ""
                    self.exportPassword = ""
                    self.confirmExportPassword = ""
                    
                } catch {
                    self.alertTitle = "Save Failed"
                    self.alertMessage = "Could not write backup file: \(error.localizedDescription)"
                    self.showAlert = true
                    self.showDontShowAgain = false
                }
            }
        }
    }
    
    // MARK: - Import Implementation
    
    func selectAndImport() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Select Backup File"
        openPanel.allowedContentTypes = [.json]
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.level = .modalPanel
        
        openPanel.begin { [weak self] response in
            guard let self = self else { return }
            
            if response == .OK, let url = openPanel.url {
                self.performImport(from: url)
            }
        }
    }
    
    private func performImport(from url: URL) {
        guard let context = context else { return }
        
        isProcessing = true
        
        Task {
            do {
                let backupData = try Data(contentsOf: url)
                
                let result = try await BackupManager.importBackup(
                    backupData: backupData,
                    masterPassword: importMasterPassword,
                    importPassword: importPassword.isEmpty ? nil : importPassword,
                    context: context,
                    replaceExisting: replaceExisting
                )
                
                await MainActor.run {
                    isProcessing = false
                    alertTitle = "✅ Import Successful"
                    alertMessage = """
                    Successfully imported:
                    • \(result.entries) passwords
                    • \(result.folders) folders
                    • \(result.with2FA) with 2FA
                    """
                    showAlert = true
                    showDontShowAgain = false
                    
                    // Clear passwords
                    importMasterPassword = ""
                    importPassword = ""
                    replaceExisting = false
                }
                
            } catch {
                await MainActor.run {
                    isProcessing = false
                    alertTitle = "Import Failed"
                    alertMessage = error.localizedDescription
                    showAlert = true
                    showDontShowAgain = false
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    func showHelp() {
        showHelpSheet = true
    }
    
    func dontShowAgain() {
        UserDefaults.standard.set(true, forKey: dontShowPlaintextWarningKey)
        alertAction?()
    }
    
    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: Date())
    }
}
