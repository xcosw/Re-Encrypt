import SwiftUI
import CoreData
import AppKit

// MARK: - FolderMode Definition (SINGLE SOURCE OF TRUTH)
enum FolderMode {
    case all
    case unfiled
    case favorites
    case twoFactor
    case specific
}

private enum ActiveSheet: Identifiable {
    case add, edit
    var id: Int { hashValue }
}

/*struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var memoryMonitor: MemoryPressureMonitor
    @EnvironmentObject private var theme: ThemeManager
    @StateObject private var securityConfig = SecurityConfigManager.shared

    let unlockToken: UnlockToken
    var onLockRequested: () -> Void = {}

    @State private var currentToken: UnlockToken?
    @State private var masterPasswordInput: String = ""
    @State private var unlockError: String?

    @State private var isLoading = false

    @State private var selectedPassword: PasswordEntry?
    @State private var activeSheet: ActiveSheet?
    @State private var selectedSidebar: SidebarSelection = .all

    @State private var showSettings = false
    @State private var showPassGen = false

    @State private var serviceName = ""
    @State private var username = ""
    @State private var password = ""
    @State private var lgdata = ""
    @State private var phn = ""
    @State private var website = ""
    @State private var category = "Other"
    @State private var countryCode = ""

    @State private var searchText: String = ""
    @State private var selectedCategory: String = "All"
    @State private var useGrid: Bool = false
    @AppStorage("Folders.useGrid") private var foldersUseGrid: Bool = true

    // MARK: - Auto-Lock Timer State
    @State private var autoLockTask: Task<Void, Never>?
    @State private var remainingTime: Int?
    @State private var autoLockGeneration: Int = 0
    @State private var lastActivityTime: Date = Date()
    @AppStorage("AutoLockEnabled") private var autoLockEnabled: Bool = false

    @FocusState private var lockFieldFocused: Bool
    @State private var eventMonitor: Any?
    
    @State private var passwordData = Data()
    @State private var passwordDisplay = ""
    
    @State private var isAttemptingUnlock = false
    @State private var isBiometricAuthenticating = false
    @State private var showBiometricPromptInLock = false
    @State private var biometricAttemptedInLock = false
    @State private var biometricError: BiometricError?

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(key: "orderIndex", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true)
        ],
        animation: .default
    )
    private var folders: FetchedResults<Folder>

    // MARK: - Computed Properties
    
    private var currentSelectedFolder: Folder? {
        if case let .folder(id) = selectedSidebar {
            return folders.first(where: { $0.objectID == id })
        }
        return nil
    }

    // FIXED: Single folderMode computed property
    private var folderMode: FolderMode {
        switch selectedSidebar {
        case .all: return .all
        case .unfiled: return .unfiled
        case .favorites: return .favorites
        case .twoFactor: return .twoFactor
        case .folder: return .specific
        }
    }

    var body: some View {
        ZStack {
            if currentToken == unlockToken {
                NavigationSplitView {
                    SidebarView(
                        selectedSidebar: $selectedSidebar,
                        foldersUseGrid: $foldersUseGrid
                    )
                } detail: {
                    detailView
                }
                .blur(radius: currentToken != unlockToken ? 10 : 0)
                .disabled(currentToken != unlockToken)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    resetAutoLock()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
                    if securityConfig.autoLockOnBackground {
                        lockApp()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .userActivityDetected)) { _ in
                    resetAutoLock()
                }
            } else {
                lockOverlay
            }

            autoLockOverlay
        }
        .onAppear {
            currentToken = unlockToken
            setupEventMonitoring()
            startAutoLockTimer()
        }
        .onDisappear { cleanup() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            if securityConfig.autoLockOnBackground {
                lockApp()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appResetRequired)) { _ in lockApp() }
        .onReceive(NotificationCenter.default.publisher(for: .applicationLocked)) { _ in lockApp() }
        .onReceive(NotificationCenter.default.publisher(for: .autoLockSettingsChanged)) { _ in
            if CryptoHelper.getAutoLockEnabled() {
                stopAutoLockTimer()
                startAutoLockTimer()
            }
        }
        .onChange(of: autoLockEnabled) { _ in resetAutoLock() }
        .appBackground()
    }

    // FIXED: Single detailView computed property
    private var detailView: some View {
        Group {
            switch selectedSidebar {
            case .all, .unfiled, .favorites, .twoFactor, .folder:
                passwordMainView
            }
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
                ToolbarItem(placement: .navigation) {
                    Button { prepareForAdd() } label: {
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
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(\.managedObjectContext, viewContext)
                .environmentObject(theme)
                .environmentObject(memoryMonitor)
                .frame(minWidth: 720, minHeight: 800)
        }
        .sheet(item: $activeSheet) { passwordFormSheet(for: $0) }
        .onChange(of: activeSheet) { newValue in
            if newValue == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.securelyErasePassword()
                }
            }
        }
        .sheet(isPresented: $showPassGen) {
            GeneratePasswordView(
                passwordData: $passwordData,
                passwordDisplay: $passwordDisplay
            )
        }
    }

    private var searchAndFilterBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(Divider(), alignment: .bottom)
    }

    private func passwordFormSheet(for sheet: ActiveSheet) -> some View {
        Group {
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
                onSave: { _ in sheet == .add ? savePassword() : updatePassword() },
                onCancel: { activeSheet = nil }
            )
            .frame(minWidth: 400, minHeight: 300)
        }
    }

    private func prepareForAdd() {
        resetForm()
        selectedPassword = nil
        activeSheet = .add
    }
    
    func savePassword() {
        guard validatePasswordForm() else { return }
        
        isLoading = true
        
        let secureStorage = SecurePasswordStorage()
        secureStorage.set(passwordData)
        
        defer {
            secureStorage.clear()
            passwordData.secureWipe()
            passwordDisplay = ""
        }
        
        guard let secureData = secureStorage.get() else {
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

    func updatePassword() {
        guard validatePasswordForm(), let entry = selectedPassword else { return }
        
        let secureStorage = SecurePasswordStorage()
        secureStorage.set(passwordData)
        
        defer {
            secureStorage.clear()
            passwordData.secureWipe()
            passwordDisplay = ""
        }
        
        guard let secureData = secureStorage.get() else {
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
        if selectedPassword == entry { selectedPassword = nil }
        CoreDataHelper.deletePassword(entry, context: viewContext)
    }

    private func editPassword(entry: PasswordEntry) {
        selectedPassword = entry
        serviceName = entry.serviceName ?? ""
        username = entry.username ?? ""
        lgdata = entry.lgdata ?? ""
        phn = entry.phn ?? ""
        website = entry.website ?? ""
        category = entry.category ?? "Other"
        
        if let decryptedData = CoreDataHelper.decryptedPasswordData(for: entry) {
            passwordData = decryptedData
            passwordDisplay = String(data: decryptedData, encoding: .utf8) ?? ""
        } else {
            passwordData = Data()
            passwordDisplay = ""
        }
    }

    private func resetForm() {
        serviceName = ""
        username = ""
        lgdata = ""
        phn = ""
        website = ""
        category = "Other"
        securelyErasePassword()
    }

    private func validatePasswordForm() -> Bool {
        !serviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !passwordData.isEmpty
    }

    // MARK: - Lock Overlay
    private var lockOverlay: some View {
        GeometryReader { geometry in
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
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
    }
    
    // MARK: - Biometric Lock View
    private var biometricLockView: some View {
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
                Text("App Locked")
                    .font(.title.bold())
                    .foregroundColor(theme.primaryTextColor)

                if isBiometricAuthenticating {
                    Text("Authenticating...")
                        .font(.subheadline)
                        .foregroundColor(theme.secondaryTextColor)
                } else if biometricAttemptedInLock {
                    Text("Authentication required")
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

                Divider()
                    .frame(width: 320)

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showBiometricPromptInLock = false
                        biometricError = nil
                        unlockError = nil
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        lockFieldFocused = true
                    }
                }) {
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

    // MARK: - Password Lock View
    private var passwordLockView: some View {
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

            VStack(spacing: 8) {
                Text("App Locked")
                    .font(.title.bold())
                    .foregroundColor(theme.primaryTextColor)

                Text("Enter your master password to continue")
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
                        .onSubmit { unlockApp() }
                }
                .padding(12)
                .background(theme.isDarkBackground ? Color.white.opacity(0.08) : Color.primary.opacity(0.06))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(lockFieldFocused ? theme.badgeBackground : Color.clear, lineWidth: 2)
                )

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
            }
            .frame(width: 320)

            Button(action: unlockApp) {
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
            .buttonStyle(.borderedProminent)
            .tint(theme.badgeBackground)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .frame(width: 320)
            .disabled(isAttemptingUnlock || masterPasswordInput.isEmpty)

            if CryptoHelper.biometricUnlockEnabled &&
               BiometricManager.shared.isBiometricAvailable &&
               BiometricManager.shared.isPasswordStored {
                VStack(spacing: 8) {
                    Divider()
                        .frame(width: 320)

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showBiometricPromptInLock = true
                            unlockError = nil
                            biometricError = nil
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            attemptBiometricUnlock()
                        }
                    }) {
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
        .appBackground()
        .background(in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
    }

    private var autoLockOverlay: some View {
        Group {
            if let time = remainingTime, currentToken == unlockToken {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()

                    VStack(spacing: 24) {
                        ZStack {
                            Circle()
                                .fill(.red.opacity(0.2))
                                .frame(width: 120, height: 120)

                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(.red.gradient)
                                .symbolEffect(.bounce.byLayer)
                        }

                        VStack(spacing: 8) {
                            Text("Auto-Lock Warning")
                                .font(.title.bold())
                                .foregroundColor(.white)

                            Text("App will lock due to inactivity")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                        }

                        ZStack {
                            Circle()
                                .stroke(.white.opacity(0.2), lineWidth: 8)
                                .frame(width: 140, height: 140)

                            Circle()
                                .trim(from: 0, to: CGFloat(time) / 20.0)
                                .stroke(.red.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                .frame(width: 140, height: 140)
                                .rotationEffect(.degrees(-90))
                                .animation(.linear(duration: 1), value: time)

                            VStack(spacing: 4) {
                                Text("\(time)")
                                    .font(.system(size: 48, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)

                                Text("seconds")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }

                        Button(action: resetAutoLock) {
                            HStack {
                                Image(systemName: "hand.raised.fill")
                                Text("Stay Active")
                            }
                            .frame(width: 200)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.white)
                    }
                    .padding(40)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                    .shadow(color: .red.opacity(0.3), radius: 30, y: 15)
                }
                .transition(.opacity.combined(with: .scale))
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: remainingTime)
            }
        }
    }

    private func unlockApp() {
        guard !masterPasswordInput.isEmpty else {
            unlockError = "Please enter your master password"
            return
        }

        isAttemptingUnlock = true
        var passwordData = Data(masterPasswordInput.utf8)
        defer {
            passwordData.resetBytes(in: 0..<passwordData.count)
            securelyEraseMasterPassword()
            isAttemptingUnlock = false
        }

        if CryptoHelper.verifyMasterPassword(password: passwordData, context: viewContext) {
            withAnimation {
                currentToken = unlockToken
                unlockError = nil
                biometricError = nil
            }
            print("[ContentView] ✅ App unlocked successfully")
            setupEventMonitoring()
            startAutoLockTimer()
        } else {
            unlockError = "Incorrect password"
            NSSound.beep()
        }
    }

    private func attemptBiometricUnlock() {
        print("[ContentView] Biometric unlock requested")
        biometricAttemptedInLock = true
        isBiometricAuthenticating = true
        biometricError = nil
        unlockError = nil

        BiometricManager.shared.authenticate { result in
            DispatchQueue.main.async {
                self.isBiometricAuthenticating = false
                
                switch result {
                case .success(let passwordData):
                    print("[ContentView] ✅ Biometric authentication successful")
                    
                    let verified = CryptoHelper.verifyMasterPassword(password: passwordData, context: self.viewContext)
                    
                    if verified {
                        withAnimation {
                            self.currentToken = self.unlockToken
                            self.unlockError = nil
                            self.biometricError = nil
                            self.showBiometricPromptInLock = false
                            self.biometricAttemptedInLock = false
                        }
                        print("[ContentView] ✅ App unlocked via biometric")
                        self.setupEventMonitoring()
                        self.startAutoLockTimer()
                    } else {
                        print("[ContentView] ❌ Biometric worked but verification failed")
                        self.biometricError = .fallback
                        self.unlockError = "Biometric authentication worked, but failed to unlock. Try your password."
                        NSSound.beep()
                    }
                    
                case .failure(let error):
                    print("[ContentView] ❌ Biometric failed: \(error.errorDescription ?? "unknown")")
                    self.biometricError = error
                    
                    switch error {
                    case .cancelled:
                        print("[ContentView] User cancelled")
                        
                    case .fallback, .unavailable:
                        print("[ContentView] Fallback to password")
                        withAnimation(.easeInOut(duration: 0.3)) {
                            self.showBiometricPromptInLock = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self.lockFieldFocused = true
                        }
                        
                    case .lockout:
                        print("[ContentView] Biometric lockout")
                        self.unlockError = "Biometric is temporarily locked. Use your password."
                        withAnimation(.easeInOut(duration: 0.3)) {
                            self.showBiometricPromptInLock = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self.lockFieldFocused = true
                        }
                        
                    case .unknown:
                        print("[ContentView] Unknown biometric error")
                    }
                }
            }
        }
    }

    private func lockApp() {
        cleanup()
        withAnimation {
            currentToken = nil
            selectedPassword = nil
            clearSensitiveData()
            unlockError = nil
            biometricError = nil
            showBiometricPromptInLock = false
            biometricAttemptedInLock = false
        }
        CryptoHelper.clearKey()
        onLockRequested()
    }
    
    private func clearSensitiveData() {
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

    private func securelyErasePassword() {
        passwordData.secureWipe()
        passwordDisplay = ""
    }

    private func securelyEraseMasterPassword() {
        guard !masterPasswordInput.isEmpty else { return }
        masterPasswordInput = String(repeating: "\0", count: masterPasswordInput.count)
        masterPasswordInput.removeAll()
    }

    // MARK: - Auto-lock Management

    private func startAutoLockTimer() {
        // Load settings first
        let enabled = CryptoHelper.getAutoLockEnabled()
        let interval = Double(CryptoHelper.getAutoLockInterval())
        
        guard enabled, currentToken == unlockToken else {
            stopAutoLockTimer()
            return
        }
        
        // Don't restart if already running with same generation
        guard autoLockTask == nil || autoLockTask?.isCancelled == true else {
            return
        }
        
        print("[ContentView] Starting auto-lock timer: \(Int(interval))s")
        stopAutoLockTimer()
        autoLockGeneration &+= 1
        lastActivityTime = Date()

        let generation = autoLockGeneration
        let intervalSeconds = max(30, interval)
        let warningDuration = min(20, Int(intervalSeconds / 3))
        let silentDuration = intervalSeconds - Double(warningDuration)

        autoLockTask = Task {
            // Silent countdown phase
            if silentDuration > 0 {
                try? await Task.sleep(nanoseconds: UInt64(silentDuration * 1_000_000_000))
            }
            
            guard !Task.isCancelled, generation == autoLockGeneration else {
                return
            }

            // Warning countdown phase
            await MainActor.run {
                remainingTime = warningDuration
            }

            for second in stride(from: warningDuration, to: 0, by: -1) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, generation == autoLockGeneration else {
                    return
                }
                
                await MainActor.run {
                    if let time = remainingTime, time > 0 {
                        remainingTime = time - 1
                    }
                }
            }
            
            // Lock the app
            guard !Task.isCancelled, generation == autoLockGeneration else { return }
            await MainActor.run {
                print("[ContentView] 🔒 Auto-locking app")
                remainingTime = nil
                lockApp()
            }
        }
    }

    private func stopAutoLockTimer() {
        print("[ContentView] Stopping auto-lock timer")
        autoLockTask?.cancel()
        autoLockTask = nil
        remainingTime = nil
    }

    private func resetAutoLock() {
        // Load setting to check if enabled
        let enabled = CryptoHelper.getAutoLockEnabled()
        guard enabled else { return }
        
        let now = Date()
        let timeSinceLastActivity = now.timeIntervalSince(lastActivityTime)
        
        // Only reset if enough time has passed (debounce)
        guard timeSinceLastActivity > 0.5 else { return }
        
        lastActivityTime = now
        
        stopAutoLockTimer()
        
        // Only restart if we're unlocked
        if currentToken == unlockToken {
            startAutoLockTimer()
        }
    }

    private func setupEventMonitoring() {
        cleanupEventMonitor()
        
        print("[ContentView] Setting up event monitoring for auto-lock")
        
        // Monitor local events (within the app window)
        // Using notification pattern since ContentView is a struct
        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .keyDown,
            .mouseMoved,
            .leftMouseDown,
            .rightMouseDown,
            .scrollWheel,
            .leftMouseDragged,
            .rightMouseDragged
        ]) { event in
            // Post notification for activity
            NotificationCenter.default.post(name: .userActivityDetected, object: nil)
            return event
        }
        
        // Store the monitor
        eventMonitor = localMonitor
    }

    private func cleanupEventMonitor() {
        if let monitor = eventMonitor {
            print("[ContentView] Cleaning up event monitor")
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func cleanup() {
        print("[ContentView] Performing cleanup")
        stopAutoLockTimer()
        cleanupEventMonitor()
        clearSensitiveData()
    }
// MARK: - END of Auto-lock Management
    private var passwordDetailsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let entry = selectedPassword {
                PasswordDetailsView(
                    selectedPassword: entry,
                    decrypt: { CoreDataHelper.decryptedPassword(for: $0) },
                    onEdit: { editPassword(entry: $0); activeSheet = .edit },
                    onDelete: deletePassword
                )
            } else {
                emptyDetailsView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
}*/


// MARK: - ContentView Critical Security Improvements

import SwiftUI
import CoreData
import AppKit

// ==========================================
// KEY IMPROVEMENTS:
// 1. Proper SecurePasswordStorage lifecycle management
// 2. Consistent error handling with do-catch
// 3. Secure data clearing with defer blocks
// 4. Better biometric integration
// 5. Proper token expiration checking
// 6. Thread-safe auto-lock implementation
// ==========================================

@available(macOS 15.0, *)
struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var memoryMonitor: MemoryPressureMonitor
    @EnvironmentObject private var theme: ThemeManager
    @StateObject private var securityConfig = SecurityConfigManager.shared
    
    let unlockToken: UnlockToken
    var onLockRequested: () -> Void = {}
    
    // MARK: - Security State
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
    
    // MARK: - Form State
    @State private var serviceName = ""
    @State private var username = ""
    @State private var lgdata = ""
    @State private var phn = ""
    @State private var website = ""
    @State private var category = "Other"
    @State private var countryCode = ""
    
    // MARK: - Search & View State
    @State private var searchText: String = ""
    @State private var selectedCategory: String = "All"
    @State private var useGrid: Bool = false
    @AppStorage("Folders.useGrid") private var foldersUseGrid: Bool = true
    
    // MARK: - Auto-Lock State
    @State private var autoLockTask: Task<Void, Never>?
    @State private var remainingTime: Int?
    @State private var autoLockGeneration: Int = 0
    @State private var lastActivityTime: Date = Date()
    @State private var eventMonitor: Any?
    
    // MARK: - Secure Password Storage
    @StateObject private var securePasswordStorage = SecurePasswordStorage()
    @State private var passwordDisplay = ""
    
    // MARK: - Biometric State
    @FocusState private var lockFieldFocused: Bool
    @State private var isAttemptingUnlock = false
    @State private var isBiometricAuthenticating = false
    @State private var showBiometricPromptInLock = false
    @State private var biometricAttemptedInLock = false
    @State private var biometricError: BiometricError?
    
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(key: "orderIndex", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true)
        ],
        animation: .default
    )
    private var folders: FetchedResults<Folder>
    
    @State private var passwordData = Data()
    
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
            if currentToken == unlockToken, !unlockToken.isExpired {
                mainApplicationView
            } else if unlockToken.isExpired {
                Color.clear.onAppear {
                    handleTokenExpired()
                }
            } else {
                lockOverlay
            }
            
            if #available(macOS 15.0, *) {
                autoLockOverlay
            } else {
                autoLockOverlay
            }
        }
        .onAppear {
            setupInitialState()
        }
        .onDisappear {
            cleanup()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            handleAppResignActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appResetRequired)) { _ in
            lockApp()
        }
        .onReceive(NotificationCenter.default.publisher(for: .applicationLocked)) { _ in
            lockApp()
        }
        .onReceive(NotificationCenter.default.publisher(for: .autoLockSettingsChanged)) { _ in
            handleAutoLockSettingsChanged()
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
        .blur(radius: currentToken != unlockToken ? 10 : 0)
        .disabled(currentToken != unlockToken)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            resetAutoLock()
        }
        .onReceive(NotificationCenter.default.publisher(for: .userActivityDetected)) { _ in
            resetAutoLock()
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
                    do {
                        try securePasswordStorage.set(generatedData)
                        passwordDisplay = String(data: generatedData, encoding: .utf8) ?? ""
                    } catch {
                        print("❌ Failed to store generated password: \(error)")
                    }
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
           // secureStorage: securePasswordStorage,
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
        activeSheet = .add
    }
    
    private func savePassword() {
        guard validatePasswordForm() else { return }
        
        isLoading = true
        
        do {
            guard let secureData = try securePasswordStorage.get() else {
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
            
        } catch {
            print("❌ Failed to save password: \(error)")
        }
        
        isLoading = false
    }
    
    private func updatePassword() {
        guard validatePasswordForm(), let entry = selectedPassword else { return }
        
        do {
            guard let secureData = try securePasswordStorage.get() else {
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
            
        } catch {
            print("❌ Failed to update password: \(error)")
        }
    }
    
    private func deletePassword(entry: PasswordEntry) {
        if selectedPassword == entry {
            selectedPassword = nil
        }
        CoreDataHelper.deletePassword(entry, context: viewContext)
    }
    
    private func editPassword(entry: PasswordEntry) {
        selectedPassword = entry
        serviceName = entry.serviceName ?? ""
        username = entry.username ?? ""
        lgdata = entry.lgdata ?? ""
        phn = entry.phn ?? ""
        website = entry.website ?? ""
        category = entry.category ?? "Other"
        
        if let decryptedData = CoreDataHelper.decryptedPasswordData(for: entry) {
            do {
                try securePasswordStorage.set(decryptedData)
                passwordDisplay = String(data: decryptedData, encoding: .utf8) ?? ""
            } catch {
                print("❌ Failed to load password for editing: \(error)")
                securePasswordStorage.clear()
                passwordDisplay = ""
            }
        } else {
            securePasswordStorage.clear()
            passwordDisplay = ""
        }
        
        activeSheet = .edit
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
        do {
            guard !serviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            
            guard let data = try securePasswordStorage.get(), !data.isEmpty else {
                return false
            }
            
            return true
        } catch {
            print("❌ Validation error: \(error)")
            return false
        }
    }
    
    // MARK: - Password Details Section
    
    private var passwordDetailsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let entry = selectedPassword {
                PasswordDetailsView(
                    selectedPassword: entry,
                    decrypt: { CoreDataHelper.decryptedPassword(for: $0) },
                    onEdit: { editPassword(entry: $0) },
                    onDelete: deletePassword
                )
            } else {
                emptyDetailsView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
    
    // MARK: - Lock Overlay (continued in next part due to length)
}

// MARK: - Lock & Unlock Implementation Extension

@available(macOS 15.0, *)
extension ContentView {
    
    // MARK: - Lock Overlay
    
    var lockOverlay: some View {
        GeometryReader { _ in
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
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
    
    private func setupLockScreen() {
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
    
    // MARK: - Biometric Lock View
    
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
                Text("App Locked")
                    .font(.title.bold())
                    .foregroundColor(theme.primaryTextColor)
                
                if isBiometricAuthenticating {
                    Text("Authenticating...")
                        .font(.subheadline)
                        .foregroundColor(theme.secondaryTextColor)
                } else if biometricAttemptedInLock {
                    Text("Authentication required")
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
    
    // MARK: - Password Lock View
    
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
            
            VStack(spacing: 8) {
                Text("App Locked")
                    .font(.title.bold())
                    .foregroundColor(theme.primaryTextColor)
                
                Text("Enter your master password to continue")
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
                        .onSubmit { unlockApp() }
                }
                .padding(12)
                .background(theme.isDarkBackground ? Color.white.opacity(0.08) : Color.primary.opacity(0.06))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(lockFieldFocused ? theme.badgeBackground : Color.clear, lineWidth: 2)
                )
                
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
            }
            .frame(width: 320)
            
            Button(action: unlockApp) {
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
            .buttonStyle(.borderedProminent)
            .tint(theme.badgeBackground)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .frame(width: 320)
            .disabled(isAttemptingUnlock || masterPasswordInput.isEmpty)
            
            if shouldShowBiometricOption {
                biometricAlternativeButton
            }
        }
        .padding(40)
        .appBackground()
        .background(in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
    }
    
    private var shouldShowBiometricOption: Bool {
        CryptoHelper.biometricUnlockEnabled &&
        BiometricManager.shared.isBiometricAvailable &&
        BiometricManager.shared.isPasswordStored
    }
    
    private var biometricAlternativeButton: some View {
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
    
    // MARK: - Unlock Logic
    
    private func unlockApp() {
        guard !masterPasswordInput.isEmpty else {
            unlockError = "Please enter your master password"
            return
        }
        
        isAttemptingUnlock = true
        var passwordData = Data(masterPasswordInput.utf8)
        
        defer {
            passwordData.resetBytes(in: 0..<passwordData.count)
            securelyEraseMasterPassword()
            isAttemptingUnlock = false
        }
        
        if CryptoHelper.verifyMasterPassword(password: passwordData, context: viewContext) {
            withAnimation {
                currentToken = unlockToken
                unlockError = nil
                biometricError = nil
            }
            print("✅ App unlocked successfully")
            setupEventMonitoring()
            startAutoLockTimer()
        } else {
            unlockError = "Incorrect password"
            NSSound.beep()
        }
    }
    
    private func attemptBiometricUnlock() {
        print("🔐 Biometric unlock requested")
        biometricAttemptedInLock = true
        isBiometricAuthenticating = true
        biometricError = nil
        unlockError = nil
        
        BiometricManager.shared.authenticate { result in
            DispatchQueue.main.async {
                self.isBiometricAuthenticating = false
                self.handleBiometricResult(result)
            }
        }
    }
    
    private func handleBiometricResult(_ result: Result<Data, BiometricError>) {
        switch result {
        case .success(let passwordData):
            print("✅ Biometric authentication successful")
            
            let verified = CryptoHelper.verifyMasterPassword(
                password: passwordData,
                context: viewContext
            )
            
            if verified {
                withAnimation {
                    currentToken = unlockToken
                    unlockError = nil
                    biometricError = nil
                    showBiometricPromptInLock = false
                    biometricAttemptedInLock = false
                }
                print("✅ App unlocked via biometric")
                setupEventMonitoring()
                startAutoLockTimer()
            } else {
                print("❌ Biometric succeeded but verification failed")
                biometricError = .fallback
                unlockError = "Authentication failed. Try your password."
                NSSound.beep()
            }
            
        case .failure(let error):
            print("❌ Biometric failed: \(error.errorDescription ?? "unknown")")
            biometricError = error
           // handleBiometricFailure(error)
        }
    }
    
    @available(macOS 15.0, *)
    private var autoLockOverlay: some View {
        Group {
            if let time = remainingTime, currentToken == unlockToken {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()

                    VStack(spacing: 24) {
                        ZStack {
                            Circle()
                                .fill(.red.opacity(0.2))
                                .frame(width: 120, height: 120)

                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(.red.gradient)
                                .symbolEffect(.bounce.byLayer)
                        }

                        VStack(spacing: 8) {
                            Text("Auto-Lock Warning")
                                .font(.title.bold())
                                .foregroundColor(.white)

                            Text("App will lock due to inactivity")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                        }

                        ZStack {
                            Circle()
                                .stroke(.white.opacity(0.2), lineWidth: 8)
                                .frame(width: 140, height: 140)

                            Circle()
                                .trim(from: 0, to: CGFloat(time) / 20.0)
                                .stroke(.red.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                .frame(width: 140, height: 140)
                                .rotationEffect(.degrees(-90))
                                .animation(.linear(duration: 1), value: time)

                            VStack(spacing: 4) {
                                Text("\(time)")
                                    .font(.system(size: 48, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)

                                Text("seconds")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }

                        Button(action: resetAutoLock) {
                            HStack {
                                Image(systemName: "hand.raised.fill")
                                Text("Stay Active")
                            }
                            .frame(width: 200)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.white)
                    }
                    .padding(40)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                    .shadow(color: .red.opacity(0.3), radius: 30, y: 15)
                }
                .transition(.opacity.combined(with: .scale))
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: remainingTime)
            }
        }
    }
    
    private func resetAutoLock() {
        // Load setting to check if enabled
        let enabled = CryptoHelper.getAutoLockEnabled()
        guard enabled else { return }
        
        let now = Date()
        let timeSinceLastActivity = now.timeIntervalSince(lastActivityTime)
        
        // Only reset if enough time has passed (debounce)
        guard timeSinceLastActivity > 0.5 else { return }
        
        lastActivityTime = now
        
        stopAutoLockTimer()
        
        // Only restart if we're unlocked
        if currentToken == unlockToken {
            startAutoLockTimer()
        }
    }

    private func stopAutoLockTimer() {
        print("[ContentView] Stopping auto-lock timer")
        autoLockTask?.cancel()
        autoLockTask = nil
        remainingTime = nil
    }
    
    // MARK: - Auto-lock Management

    private func startAutoLockTimer() {
        // Load settings first
        let enabled = CryptoHelper.getAutoLockEnabled()
        let interval = Double(CryptoHelper.getAutoLockInterval())
        
        guard enabled, currentToken == unlockToken else {
            stopAutoLockTimer()
            return
        }
        
        // Don't restart if already running with same generation
        guard autoLockTask == nil || autoLockTask?.isCancelled == true else {
            return
        }
        
        print("[ContentView] Starting auto-lock timer: \(Int(interval))s")
        stopAutoLockTimer()
        autoLockGeneration &+= 1
        lastActivityTime = Date()

        let generation = autoLockGeneration
        let intervalSeconds = max(30, interval)
        let warningDuration = min(20, Int(intervalSeconds / 3))
        let silentDuration = intervalSeconds - Double(warningDuration)

        autoLockTask = Task {
            // Silent countdown phase
            if silentDuration > 0 {
                try? await Task.sleep(nanoseconds: UInt64(silentDuration * 1_000_000_000))
            }
            
            guard !Task.isCancelled, generation == autoLockGeneration else {
                return
            }

            // Warning countdown phase
            await MainActor.run {
                remainingTime = warningDuration
            }

            for second in stride(from: warningDuration, to: 0, by: -1) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, generation == autoLockGeneration else {
                    return
                }
                
                await MainActor.run {
                    if let time = remainingTime, time > 0 {
                        remainingTime = time - 1
                    }
                }
            }
            
            // Lock the app
            guard !Task.isCancelled, generation == autoLockGeneration else { return }
            await MainActor.run {
                print("[ContentView] 🔒 Auto-locking app")
                remainingTime = nil
                lockApp()
            }
        }
    }
    
    private func setupEventMonitoring() {
        cleanupEventMonitor()
        
        print("[ContentView] Setting up event monitoring for auto-lock")
        
        // Monitor local events (within the app window)
        // Using notification pattern since ContentView is a struct
        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .keyDown,
            .mouseMoved,
            .leftMouseDown,
            .rightMouseDown,
            .scrollWheel,
            .leftMouseDragged,
            .rightMouseDragged
        ]) { event in
            // Post notification for activity
            NotificationCenter.default.post(name: .userActivityDetected, object: nil)
            return event
        }
        
        // Store the monitor
        eventMonitor = localMonitor
    }

    private func cleanupEventMonitor() {
        if let monitor = eventMonitor {
            print("[ContentView] Cleaning up event monitor")
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    private func lockApp() {
        cleanup()
        withAnimation {
            currentToken = nil
            selectedPassword = nil
            clearSensitiveData()
            unlockError = nil
            biometricError = nil
            showBiometricPromptInLock = false
            biometricAttemptedInLock = false
        }
        CryptoHelper.clearKey()
        onLockRequested()
    }
    
    private func clearSensitiveData() {
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
    
    private func securelyErasePassword() {
        passwordData.secureWipe()
        passwordDisplay = ""
    }

    private func securelyEraseMasterPassword() {
        guard !masterPasswordInput.isEmpty else { return }
        masterPasswordInput = String(repeating: "\0", count: masterPasswordInput.count)
        masterPasswordInput.removeAll()
    }
    
    private func cleanup() {
        print("[ContentView] Performing cleanup")
        stopAutoLockTimer()
        cleanupEventMonitor()
        clearSensitiveData()
    }
    
    private func handleTokenExpired() {
        print("🔒 Unlock token expired – locking app")
        lockApp()
    }

    private func setupInitialState() {
        print("[ContentView] Setting up initial state")

        // If token is valid, set currentToken
        if !unlockToken.isExpired {
            currentToken = unlockToken
            setupEventMonitoring()
            startAutoLockTimer()
        } else {
            currentToken = nil
        }
    }

    private func handleAppResignActive() {
        print("[ContentView] App resigned active – locking immediately")
        lockApp()
    }
    
    private func handleAutoLockSettingsChanged() {
        print("[ContentView] Auto-lock settings changed – restarting timer")
        resetAutoLock()
    }
    
    private func switchToPasswordEntry() {
        withAnimation {
            showBiometricPromptInLock = false
            lockFieldFocused = true
            biometricError = nil
        }
    }

    private func switchToBiometric() {
        withAnimation {
            showBiometricPromptInLock = true
            biometricError = nil
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            attemptBiometricUnlock()
        }
    }

    
}
