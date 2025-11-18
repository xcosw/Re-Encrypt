import SwiftUI

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
    
    private func performExport() {
        isProcessing = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let password = useExportPassword ? (exportPassword.isEmpty ? nil : exportPassword) : nil
                
                let backupData = try BackupManager.exportBackup(
                    context: viewContext,
                    masterPassword: masterPassword,
                    exportPassword: password,
                    decryptBeforeExport: !useExportPassword && decryptBeforeExport
                )
                
                DispatchQueue.main.async {
                    saveBackupFile(data: backupData)
                    isProcessing = false
                }
            } catch {
                DispatchQueue.main.async {
                    alertTitle = "Export Failed"
                    alertMessage = error.localizedDescription
                    showAlert = true
                    isProcessing = false
                }
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
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try Data(contentsOf: url)
                
                let pwd = importPassword.isEmpty ? nil : importPassword
                
                let (entries, folders) = try BackupManager.importBackup(
                    backupData: data,
                    masterPassword: importMasterPassword,
                    importPassword: pwd,
                    context: viewContext,
                    replaceExisting: replaceExisting
                )
                
                DispatchQueue.main.async {
                    alertTitle = "✅ Import Successful"
                    alertMessage = """
                    Backup restored successfully!
                    
                    📁 Folders imported: \(folders)
                    🔑 Passwords imported: \(entries)
                    
                    File: \(url.lastPathComponent)
                    """
                    showAlert = true
                    isProcessing = false
                    
                    // Clear passwords
                    clearImportForm()
                }
            } catch {
                DispatchQueue.main.async {
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

// MARK: - Settings Integration

/*
Usage in your SettingsView:

Replace the backup section with:

private var backupSection: some View {
    CardSection(title: "Backup", icon: "arrow.up.doc.fill") {
        Button {
            BackupWindow.open(context: context)
        } label: {
            Label("Backup & Restore", systemImage: "externaldrive.fill")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderedProminent)
    }
}

Make sure you have @Environment(\.managedObjectContext) private var context in your SettingsView.
*/
