import SwiftUI
import CoreData
import AppKit

private enum ActiveSheet: Identifiable {
    case add, edit
    var id: Int { hashValue }
}

enum FolderMode {
    case all, unfiled, favorites, twoFactor, specific
}

@available(macOS 15.0, *)
struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var memoryMonitor: MemoryPressureMonitor
    @EnvironmentObject private var theme: ThemeManager
    @StateObject private var securityConfig = SecurityConfigManager.shared
    @StateObject private var screenshotDetector = ScreenshotDetectionManager.shared
    
    // MARK: - Form State
    @State private var showInlineAddForm: Bool = false
    @State private var showInlineEditForm: Bool = false
    @State private var editingEntry: PasswordEntry? = nil
    
    let unlockToken: UnlockToken
    var onLockRequested: () -> Void = {}
    
    // MARK: - Lock State
    @State private var isLocked = false
    @State private var lockReason: AppState.LockReason = .manual
    @State private var currentToken: UnlockToken?
    @State private var masterPasswordInput: String = ""
    @State private var unlockError: String?
    
    // MARK: - UI State
    @State private var isLoading = false
    @State private var selectedPassword: PasswordEntry?
    @State private var activeSheet: ActiveSheet?
    @State private var selectedSidebar: SidebarSelection = .all
    @State private var showSettings = false
    @State private var showPassGen = false
    @State private var lastLockReason: AppState.LockReason?
    
    // MARK: - Form Fields
    @State private var serviceName = ""
    @State private var username = ""
    @State private var lgdata = ""
    @State private var phn = ""
    @State private var website = ""
    @State private var category = "Other"
    @State private var countryCode = ""
    
    // MARK: - Search & View
    @State private var searchText: String = ""
    @State private var selectedCategory: String = "All"
    @State private var useGrid: Bool = false
    @AppStorage("Folders.useGrid") private var foldersUseGrid: Bool = true
    
   
    // MARK: - Password Storage
    @StateObject private var securePasswordStorage = SecurePasswordStorage()
    @State private var passwordDisplay = ""
    @State private var passwordData = Data()
    
    // MARK: - Biometric
    @FocusState private var lockFieldFocused: Bool
    @State private var isAttemptingUnlock = false
    @State private var isBiometricAuthenticating = false
    @State private var showBiometricPromptInLock = false
    @State private var biometricAttemptedInLock = false
    @State private var biometricError: BiometricError?
    
    // MARK: - UI State
    @State private var lockoutTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool
    @State private var lockoutTimeRemaining: Int = 0
    @State private var failedAttempts: Int = 0
    //@State private var errorMessage: String?
    
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(key: "orderIndex", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true)
        ],
        animation: .default
    )
    private var folders: FetchedResults<Folder>
    let onRequireSetup: () -> Void
    
    // MARK: - Computed Properties
    
    private var currentSelectedFolder: Folder? {
        if case let .folder(id) = selectedSidebar {
            return folders.first(where: { $0.objectID == id })
        }
        return nil
    }
    
    private var folderMode: FolderMode {
        switch selectedSidebar {
        case .all: return .all
        case .unfiled: return .unfiled
        case .favorites: return .favorites
        case .twoFactor: return .twoFactor
        case .folder: return .specific
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            if !isLocked && currentToken == unlockToken && !unlockToken.isExpired {
                mainApplicationView
                    .blur(radius: 0)
            } else if unlockToken.isExpired {
                Color.clear.onAppear {
                    handleTokenExpired()
                }
            }
            
            // Local lock overlay
            if isLocked {
                lockOverlay
                    .transition(.opacity)
                    .zIndex(100)
            }
            
        }
        .animation(.easeInOut(duration: 0.3), value: isLocked)
        .onAppear {
            setupInitialState()
            loadSettings()
        }
        .onDisappear {
            cleanup()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            handleAppResignActive()
        }

        .onReceive(NotificationCenter.default.publisher(for: .appResetRequired)) { _ in
            lockAppLocally(reason: .manual)
        }
        .onReceive(NotificationCenter.default.publisher(for: .applicationLocked)) { _ in
            lockAppLocally(reason: .manual)
        }
        .onReceive(NotificationCenter.default.publisher(for: .sessionExpired)) { _ in
            handleSessionExpired()
        }
        .onReceive(NotificationCenter.default.publisher(for: .memoryPressureDetected)) { _ in
            handleMemoryPressure()
        }
        .appBackground()
    }
    
    // MARK: - Main Application View
    
    private var mainApplicationView: some View {
        NavigationSplitView {
            SidebarView(
                selectedSidebar: $selectedSidebar,
                foldersUseGrid: $foldersUseGrid
            )
        } detail: {
            passwordMainView
        }
    }
    
    private var passwordMainView: some View {
        VStack(spacing: 0) {
            Divider()
                .background(.clear)
                .appBackground()
            
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    searchAndFilterBar
                    PasswordListView(
                        onDelete: deletePassword,
                        selectedPassword: $selectedPassword,
                        folderMode: .constant(folderMode),
                        selectedFolderID: .constant(currentSelectedFolder?.objectID),
                        searchText: $searchText,
                        selectedCategory: $selectedCategory,
                        useGrid: $useGrid
                    )
                    .layoutPriority(1)
                }
                .frame(minWidth: 220, maxWidth: 270)
                .overlay(Divider(), alignment: .trailing)
                
                passwordDetailsSection
                    .appBackground()
            }
            .toolbar {
                toolbarContent
            }
        }
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
        .sheet(item: $activeSheet) { sheet in
            passwordFormSheet(for: sheet)
        }
        .onChange(of: activeSheet) { _, newValue in
            if newValue == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    securePasswordStorage.clear()
                    passwordDisplay = ""
                }
            }
        }
        .sheet(isPresented: $showPassGen) {
            GeneratePasswordView(
                passwordData: $passwordData,
                passwordDisplay: $passwordDisplay,
                onGenerated: { generatedData in
                    securePasswordStorage.set(generatedData)
                    passwordDisplay = String(data: generatedData, encoding: .utf8) ?? ""
                }
            )
        }
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                prepareForAdd()
            } label: {
                Image(systemName: "plus")
                    .foregroundColor(theme.badgeBackground)
            }
        }
        
        ToolbarItem(placement: .automatic) {
            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .foregroundColor(theme.primaryTextColor)
            }
            .help("Open Settings")
        }
        
        ToolbarItem(placement: .primaryAction) {
            Button {
                showPassGen = true
            } label: {
                Label("Generate Password", systemImage: "key.fill")
                    .foregroundColor(theme.badgeBackground)
            }
        }
        
        ToolbarItem(placement: .status) {
            SecurityStatusIndicator()
                .environmentObject(memoryMonitor)
        }
    }
    
    // MARK: - Settings Sheet
    
    private var settingsSheet: some View {
        SettingsView()
            .environment(\.managedObjectContext, viewContext)
            .environmentObject(theme)
            .environmentObject(memoryMonitor)
            .environmentObject(screenshotDetector)
            .frame(minWidth: 720, minHeight: 800)
    }
    
    // MARK: - Search Bar
    
    private var searchAndFilterBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                searchField
                layoutToggle
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(Divider(), alignment: .bottom)
    }
    
    private var searchField: some View {
        ZStack(alignment: .leading) {
            if searchText.isEmpty {
                Text("Search passwords...")
                    .foregroundColor(theme.secondaryTextColor.opacity(0.6))
                    .padding(.leading, 28)
            }
            
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(theme.badgeBackground)
                    .font(.body)
                
                TextField("", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundColor(theme.primaryTextColor)
                    .disableAutocorrection(true)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(theme.secondaryTextColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                theme.isDarkBackground
                    ? Color.white.opacity(0.08)
                    : Color.primary.opacity(0.06)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.badgeBackground.opacity(0.4), lineWidth: 1)
            )
            .cornerRadius(8)
        }
    }
    
    private var layoutToggle: some View {
        HStack(spacing: 0) {
            Button {
                useGrid = false
            } label: {
                Image(systemName: "list.bullet")
                    .frame(width: 40, height: 24)
                    .background(useGrid ? .clear : theme.badgeBackground)
                    .foregroundStyle(useGrid ? theme.primaryTextColor : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            
            Button {
                useGrid = true
            } label: {
                Image(systemName: "square.grid.2x2")
                    .frame(width: 40, height: 24)
                    .background(useGrid ? theme.badgeBackground : .clear)
                    .foregroundStyle(useGrid ? .white : theme.primaryTextColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(theme.badgeBackground.opacity(0.4), lineWidth: 1)
        )
        .frame(width: 80)
    }
    
    // MARK: - Password Form Sheet
    
    private func passwordFormSheet(for sheet: ActiveSheet) -> some View {
        AddPasswordForm(
            title: sheet == .add ? "Add Password" : "Edit Password",
            serviceName: $serviceName,
            username: $username,
            lgdata: $lgdata,
            website: $website,
            phn: $phn,
            countryCode: $countryCode,
            passwordData: $passwordData,
            passwordDisplay: $passwordDisplay,
            existingEntry: sheet == .edit ? selectedPassword : nil,
            selectedFolder: currentSelectedFolder,
            onSave: { _ in
                sheet == .add ? savePassword() : updatePassword()
            },
            onCancel: {
                activeSheet = nil
                securePasswordStorage.clear()
                passwordDisplay = ""
            }
        )
        .frame(minWidth: 400, minHeight: 300)
    }
    
    // MARK: - Password CRUD Operations
    
    private func prepareForAdd() {
        resetForm()
        selectedPassword = nil
        withAnimation {
            showInlineAddForm = true
            showInlineEditForm = false
            editingEntry = nil
        }
    }
    
    private func savePassword() {
        guard validatePasswordForm() else { return }
        
        isLoading = true
        
        guard let secureData = securePasswordStorage.get() else {
            print("❌ No password data in secure storage")
            isLoading = false
            return
        }
        
        CoreDataHelper.savePassword(
            serviceName: serviceName,
            username: username,
            lgdata: lgdata,
            countryCode: countryCode,
            phn: phn,
            website: website,
            passwordData: secureData,
            category: category.isEmpty ? "Other" : category,
            folder: currentSelectedFolder,
            notes: nil,
            isFavorite: false,
            passwordExpiry: nil,
            tags: nil,
            context: viewContext
        )
        
        resetForm()
        activeSheet = nil
        isLoading = false
    }
    
    private func updatePassword() {
        guard validatePasswordForm(), let entry = selectedPassword else { return }
        
        guard let secureData = securePasswordStorage.get() else {
            print("❌ No password data in secure storage")
            return
        }
        
        CoreDataHelper.upsertPassword(
            entry: entry,
            serviceName: serviceName,
            username: username,
            lgdata: lgdata,
            countryCode: countryCode,
            phn: phn,
            website: website,
            passwordData: secureData,
            category: category.isEmpty ? (entry.category ?? "Other") : category,
            folder: currentSelectedFolder,
            notes: entry.notes,
            isFavorite: entry.isFavorite,
            passwordExpiry: entry.passwordExpiry,
            tags: entry.tags,
            context: viewContext
        )
        
        resetForm()
        activeSheet = nil
    }
    
    private func deletePassword(entry: PasswordEntry) {
        if selectedPassword == entry {
            selectedPassword = nil
        }
        CoreDataHelper.deletePassword(entry, context: viewContext)
    }
    
    private func editPassword(entry: PasswordEntry) {
        selectedPassword = entry
        editingEntry = entry
        serviceName = entry.serviceName ?? ""
        username = entry.username ?? ""
        lgdata = entry.lgdata ?? ""
        phn = entry.phn ?? ""
        website = entry.website ?? ""
        category = entry.category ?? "Other"
        countryCode = entry.countryCode ?? ""
        
        if let decryptedData = CoreDataHelper.decryptedPasswordData(for: entry) {
            print("✅ Loaded password data: \(decryptedData.count) bytes")
            securePasswordStorage.set(decryptedData)
            passwordData = decryptedData
            passwordDisplay = String(data: decryptedData, encoding: .utf8) ?? ""
        } else {
            print("❌ Failed to decrypt password for editing")
            securePasswordStorage.clear()
            passwordData = Data()
            passwordDisplay = ""
        }
        
        withAnimation {
            showInlineAddForm = false
            showInlineEditForm = true
        }
    }
    
    private func resetForm() {
        serviceName = ""
        username = ""
        lgdata = ""
        phn = ""
        website = ""
        category = "Other"
        securePasswordStorage.clear()
        passwordDisplay = ""
    }
    
    private func validatePasswordForm() -> Bool {
        guard !serviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        
        guard let data = securePasswordStorage.get(), !data.isEmpty else {
            return false
        }
        
        return true
    }
    
    // MARK: - Password Details Section
    
    private var passwordDetailsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showInlineAddForm {
                ScrollView {
                    AddPasswordForm(
                        title: "Add New Password",
                        serviceName: $serviceName,
                        username: $username,
                        lgdata: $lgdata,
                        website: $website,
                        phn: $phn,
                        countryCode: $countryCode,
                        passwordData: $passwordData,
                        passwordDisplay: $passwordDisplay,
                        existingEntry: nil,
                        selectedFolder: currentSelectedFolder,
                        onSave: { updatedData in
                            passwordData = updatedData
                            savePassword()
                            withAnimation {
                                showInlineAddForm = false
                            }
                        },
                        onCancel: {
                            withAnimation {
                                showInlineAddForm = false
                            }
                            resetForm()
                        }
                    )
                    .padding()
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
                
            } else if showInlineEditForm, let entry = editingEntry {
                ScrollView {
                    AddPasswordForm(
                        title: "Edit Password",
                        serviceName: $serviceName,
                        username: $username,
                        lgdata: $lgdata,
                        website: $website,
                        phn: $phn,
                        countryCode: $countryCode,
                        passwordData: $passwordData,
                        passwordDisplay: $passwordDisplay,
                        existingEntry: entry,
                        selectedFolder: currentSelectedFolder,
                        onSave: { updatedData in
                            passwordData = updatedData
                            updatePassword()
                            withAnimation {
                                showInlineEditForm = false
                                editingEntry = nil
                            }
                        },
                        onCancel: {
                            withAnimation {
                                showInlineEditForm = false
                                editingEntry = nil
                            }
                            resetForm()
                        }
                    )
                    .padding()
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
                
            } else if let entry = selectedPassword {
                Group {
                    if selectedSidebar == .twoFactor {
                        PasswordQuickDetailView(entry: entry)
                            .environmentObject(theme)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    } else {
                        PasswordDetailsView(
                            selectedPassword: entry,
                            decrypt: { CoreDataHelper.decryptedPassword(for: $0) },
                            onEdit: { editPassword(entry: $0) },
                            onDelete: deletePassword
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: selectedSidebar)
                
            } else {
                emptyDetailsView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.3), value: showInlineAddForm)
        .animation(.easeInOut(duration: 0.3), value: showInlineEditForm)
    }
    
    private var emptyDetailsView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(theme.badgeBackground.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(theme.badgeBackground.gradient)
            }
            
            VStack(spacing: 8) {
                Text("No Password Selected")
                    .font(.title2.bold())
                    .foregroundColor(theme.primaryTextColor)
                
                Text("Select a password from the list to view its details")
                    .font(.subheadline)
                    .foregroundColor(theme.secondaryTextColor)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
            
            HStack(spacing: 12) {
                Button(action: prepareForAdd) {
                    Label("Add New", systemImage: "plus.circle.fill")
                        .foregroundColor(theme.secondaryTextColor)
                        .tint(theme.badgeBackground)
                }
                .buttonStyle(.bordered)
                
                Button(action: { showPassGen = true }) {
                    Label("Generate", systemImage: "key.fill")
                        .foregroundColor(theme.secondaryTextColor)
                        .tint(theme.badgeBackground)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Lock & Security Extension

@available(macOS 15.0, *)
private extension ContentView {
    
    // MARK: - Lock/Unlock
    
    func lockAppLocally(reason: AppState.LockReason) {
        print("🔒 Locking app locally (reason: \(reason))")
        
        cleanup()
        
        withAnimation {
            isLocked = true
            lastLockReason = lockReason
            lockReason = reason
            currentToken = unlockToken
            selectedPassword = nil
            clearSensitiveData()
            unlockError = nil
            biometricError = nil
            showBiometricPromptInLock = false
            biometricAttemptedInLock = false
        }
        
        CryptoHelper.clearKey()
        
        print("✅ App is now locked with overlay, app remains running")
        
        // Only escalate to full lock for critical reasons (NOT auto-lock)
        switch reason {
        case .sessionTimeout, .memoryPressure, .tokenExpired:
            print("⚠️ Critical lock reason - escalating to full app lock")
            onLockRequested()
        case .autoLock, .background, .manual, .normal:
            print("ℹ️ Non-critical lock - staying in ContentView with overlay")
        case .maxAttempts:
            print("ℹ️ critical lock - erasing all user data")
   
        }
    }
    
    func unlockAppLocally() async {
        guard !masterPasswordInput.isEmpty else {
            unlockError = "Please enter your master password"
            return
        }
        
        isAttemptingUnlock = true
        defer {
            masterPasswordInput = ""
            securelyEraseMasterPassword()
            isAttemptingUnlock = false
        }
        
        var passwordData = Data(masterPasswordInput.utf8)
        defer { passwordData.secureWipe() }
        
        let success = await CryptoHelper.verifyMasterPassword(
            password: passwordData,
            context: viewContext
        )
        
        if success {
            print("✅ App unlocked locally")
            
            // ✅ FIXED: Reset failed attempts on successful unlock
            CryptoHelper.failedAttempts = 0
            failedAttempts = 0
            lockoutTimeRemaining = 0
            lockoutTask?.cancel()
            
            withAnimation(.easeInOut(duration: 0.3)) {
                isLocked = false
                unlockError = nil
                biometricError = nil
            }
            
        } else {
            
            CryptoHelper.failedAttempts += 1
            failedAttempts = CryptoHelper.failedAttempts
            
            unlockError = "Incorrect password (Attempt \(failedAttempts)/\(CryptoHelper.maxAttempts))"
            NSSound.beep()
            
            if failedAttempts >= CryptoHelper.maxAttempts {
                // Max attempts reached
                print("❌ Max attempts reached - requiring setup")
                CryptoHelper.failedAttempts = 0
                lockAppLocally(reason: .maxAttempts)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    onRequireSetup()
                }
            } else if failedAttempts >= 3 {
                // Apply progressive lockout
                applyLockout()
            }
        }
        
        securePasswordStorage.clear()
    }
    
    // MARK: - Lock Overlay
    
    var lockOverlay: some View {
        GeometryReader { _ in
            ZStack {
                //VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                VisualEffectView(material: .popover, blendingMode: .behindWindow)

                    .ignoresSafeArea()
                
                if showBiometricPromptInLock {
                    biometricLockView
                } else {
                    passwordLockView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            setupLockScreen()
        }
    }
    
    func setupLockScreen() {
        if CryptoHelper.biometricUnlockEnabled &&
           BiometricManager.shared.isBiometricAvailable &&
           BiometricManager.shared.isPasswordStored {
            showBiometricPromptInLock = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                attemptBiometricUnlock()
            }
        } else {
            showBiometricPromptInLock = false
            lockFieldFocused = true
        }
    }
    
    var biometricLockView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(theme.badgeBackground.opacity(0.2))
                    .frame(width: 100, height: 100)
                
                Image(systemName: BiometricManager.shared.biometricSystemImage())
                    .font(.system(size: 48))
                    .foregroundStyle(theme.badgeBackground.gradient)
                    .symbolEffect(.pulse)
            }
            
            VStack(spacing: 8) {
                Text(lockReason.message)
                    .font(.title.bold())
                    .foregroundColor(theme.primaryTextColor)
                
                if let lastReason = lastLockReason, lastReason != lockReason {
                    Text("Previous: \(lastReason.message)")
                        .font(.caption)
                        .foregroundColor(theme.secondaryTextColor.opacity(0.7))
                }
                
                if isBiometricAuthenticating {
                    Text("Authenticating...")
                        .font(.subheadline)
                        .foregroundColor(theme.secondaryTextColor)
                } else {
                    Text("Use \(BiometricManager.shared.biometricDisplayName()) to unlock")
                        .font(.subheadline)
                        .foregroundColor(theme.secondaryTextColor)
                }
            }
            
            VStack(spacing: 16) {
                Button(action: attemptBiometricUnlock) {
                    HStack {
                        if isBiometricAuthenticating {
                            ProgressView()
                                .scaleEffect(0.8)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: BiometricManager.shared.biometricSystemImage())
                            Text("Unlock with \(BiometricManager.shared.biometricDisplayName())")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.badgeBackground)
                .controlSize(.large)
                .frame(width: 320)
                .disabled(isBiometricAuthenticating)
                
                if let biometricError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(biometricError.errorDescription ?? "Authentication failed")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .transition(.opacity.combined(with: .scale))
                }
                
                Divider().frame(width: 320)
                
                Button(action: switchToPasswordEntry) {
                    HStack {
                        Image(systemName: "key.fill")
                        Text("Use Master Password Instead")
                    }
                }
                .buttonStyle(.bordered)
                .tint(theme.badgeBackground)
                .frame(width: 320)
                .disabled(isBiometricAuthenticating)
            }
        }
        .padding(40)
        .appBackground()
        .background(in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
    }
    
    var passwordLockView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(theme.badgeBackground.opacity(0.2))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(theme.badgeBackground.gradient)
                    .symbolEffect(.pulse)
            }
            
            // ✅ FIXED: Simplified lock reason display
            VStack(spacing: 8) {
                Text(lockReason.message)
                    .font(.title.bold())
                    .foregroundColor(theme.primaryTextColor)
                
                // Show previous lock reason only if meaningful
                if let lastReason = lastLockReason,
                   lastReason != lockReason,
                   lockReason != .maxAttempts {
                    Text("Previous: \(lastReason.message)")
                        .font(.caption)
                        .foregroundColor(theme.secondaryTextColor.opacity(0.7))
                }
                
                // ✅ FIXED: Contextual subtitle based on lock reason
                Text(lockMessageSubtitle)
                    .font(.subheadline)
                    .foregroundColor(theme.secondaryTextColor)
            }
            
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "key.fill")
                        .foregroundColor(theme.secondaryTextColor)
                    
                    SecureField("Master Password", text: $masterPasswordInput)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .focused($lockFieldFocused)
                        .onSubmit {
                            Task { @MainActor in
                                await unlockAppLocally()
                            }
                        }
                        .disabled(lockoutTimeRemaining > 0)
                }
                .padding(12)
                .background(theme.isDarkBackground ? Color.white.opacity(0.08) : Color.primary.opacity(0.06))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isFocused ? theme.badgeBackground : Color.clear, lineWidth: 2)
                )
                
                // Error message
                if let unlockError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(unlockError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .transition(.opacity)
                }
                
                // Lockout timer
                if lockoutTimeRemaining > 0 {
                    HStack {
                        Image(systemName: "clock.fill")
                            .foregroundColor(.orange)
                        Text("Locked for \(lockoutTimeRemaining) seconds")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .transition(.opacity)
                }
            }
            .frame(width: 320)
            
            Button {
                Task { @MainActor in
                    await unlockAppLocally()
                }
            } label: {
                HStack {
                    if isAttemptingUnlock {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "lock.open.fill")
                        Text("Unlock")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(isAttemptingUnlock || masterPasswordInput.isEmpty || lockoutTimeRemaining > 0)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .frame(width: 320)
            
            if CryptoHelper.biometricUnlockEnabled &&
                BiometricManager.shared.isBiometricAvailable &&
                BiometricManager.shared.isPasswordStored {
                VStack(spacing: 8) {
                    Divider().frame(width: 320)
                    
                    Button(action: switchToBiometric) {
                        HStack {
                            Image(systemName: BiometricManager.shared.biometricSystemImage())
                            Text("Use \(BiometricManager.shared.biometricDisplayName()) Instead")
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(theme.badgeBackground)
                    .frame(width: 320)
                }
            }
        }
        .padding(40)
    }
    
// MARK: Helper for contextual subtitle
    private var lockMessageSubtitle: String {
        switch lockReason {
        case .maxAttempts:
            return "Account will be reset for security"
        case .memoryPressure:
            return "Enter password to resume"
        case .sessionTimeout:
            return "Enter password to continue"
        case .tokenExpired:
            return "Enter password to continue"
        case .background:
            return "Unlock to continue"
        case .autoLock:
            return "Enter password to unlock"
        default:
            return "Enter your master password to continue"
        }
    }
     
     func attemptBiometricUnlock() {
         print("🔐 Biometric unlock requested")
         biometricAttemptedInLock = true
         isBiometricAuthenticating = true
         biometricError = nil
         unlockError = nil
         
         Task { @MainActor in
             let result = await BiometricManager.shared.authenticate()
             await handleBiometricResult(result)
             isBiometricAuthenticating = false
         }
     }
     
// MARK: - handleBiometricResult
    func handleBiometricResult(_ result: Result<Data, BiometricError>) async {
        switch result {
        case .success(let passwordData):
            print("✅ Biometric authentication successful")
            
            try? await Task.sleep(nanoseconds: 200_000_000)
            
            let verified = await CryptoHelper.verifyMasterPassword(
                password: passwordData,
                context: viewContext
            )
            
            if verified {
                print("✅ App unlocked locally via biometric")
                
                // ✅ FIXED: Reset failed attempts on biometric success
                CryptoHelper.failedAttempts = 0
                failedAttempts = 0
                lockoutTimeRemaining = 0
                lockoutTask?.cancel()
                
                withAnimation(.easeInOut(duration: 0.3)) {
                    isLocked = false
                    unlockError = nil
                    biometricError = nil
                    showBiometricPromptInLock = false
                    biometricAttemptedInLock = false
                }
                
            } else {
                print("❌ Biometric succeeded but password verification failed")
                biometricError = .fallback
                unlockError = "Authentication failed. Please use your password."
                NSSound.beep()
            }
            
            self.passwordData.secureWipe()
            
        case .failure(let error):
            print("❌ Biometric failed: \(error.errorDescription ?? "unknown")")
            biometricError = error
        }
    }
     
     func switchToPasswordEntry() {
         withAnimation {
             showBiometricPromptInLock = false
             lockFieldFocused = true
             biometricError = nil
         }
     }
     
     func switchToBiometric() {
         withAnimation {
             showBiometricPromptInLock = true
             biometricError = nil
         }
         
         DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
             attemptBiometricUnlock()
         }
     }
    // MARK: - Failed Attempts & Lockout
    private func applyLockout() {
        let lockoutDuration = min(30, failedAttempts * 5)
        lockoutTimeRemaining = lockoutDuration
            
        lockoutTask = Task {
            for _ in 0..<lockoutDuration {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    if lockoutTimeRemaining > 0 {
                            lockoutTimeRemaining -= 1
                    }
                }
            }
        }
    }
    
// MARK: - Event Handlers
     
     func handleTokenExpired() {
         print("🔒 Unlock token expired")
         lockAppLocally(reason: .tokenExpired)
     }
     
     func handleSessionExpired() {
         print("⏰ Session expired in ContentView")
         lockAppLocally(reason: .sessionTimeout)
     }
     
     func handleMemoryPressure() {
         print("⚠️ Memory pressure in ContentView")
         lockAppLocally(reason: .memoryPressure)
     }
     
     func handleAppResignActive() {
         Task { @MainActor in
             let shouldLock = securityConfig.autoLockOnBackground
             print("[ContentView] App resigned active – shouldLock: \(shouldLock)")
             
             if shouldLock {
                 print("[ContentView] Locking app due to background setting")
                 lockAppLocally(reason: .background)
             }
         }
     }
     
     // MARK: - Setup & Cleanup
     
    func setupInitialState() {
        print("🚀 [ContentView] Setting up initial state")
        
        isLocked = false
        
        if !unlockToken.isExpired {
            currentToken = unlockToken
            
            print("✅ [ContentView] Token is valid, setting up security")
            
            // Setup event monitoring FIRST
         
            
            // Then start auto-lock timer
            let autoLockEnabled = CryptoHelper.getAutoLockEnabled()
            print("📋 [ContentView] Auto-lock enabled: \(autoLockEnabled)")
            
        } else {
            print("❌ [ContentView] Token expired")
            currentToken = nil
            lockAppLocally(reason: .tokenExpired)
        }
    }
     
     func loadSettings() {
         DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
             let autoLockEnabled = CryptoHelper.getAutoLockEnabled()
             let autoLockInterval = CryptoHelper.getAutoLockInterval()
             let sessionTimeout = CryptoHelper.getSessionTimeout()
             
             print("📋 Loaded settings:")
             print("  - Auto-lock: \(autoLockEnabled), interval: \(autoLockInterval)s")
             print("  - Session timeout: \(Int(sessionTimeout))s")
         }
     }
     
     func cleanup() {
         print("[ContentView] Performing cleanup")
         
         clearSensitiveData()
     }
     
     func clearSensitiveData() {
         DispatchQueue.main.async {
             serviceName = ""
             username = ""
             lgdata = ""
             phn = ""
             website = ""
             category = "Other"
             securelyErasePassword()
             securelyEraseMasterPassword()
         }
     }
     
     func securelyErasePassword() {
         passwordData.secureWipe()
         passwordDisplay = ""
     }
     
     func securelyEraseMasterPassword() {
         guard !masterPasswordInput.isEmpty else { return }
         masterPasswordInput = String(repeating: "\0", count: masterPasswordInput.count)
         masterPasswordInput.removeAll()
     }
 }

