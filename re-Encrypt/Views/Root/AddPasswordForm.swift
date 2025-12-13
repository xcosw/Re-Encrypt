
import SwiftUI
import CoreData

let countryCodes: [CountryCode] = CountryData.loadCountryCodes()

@available(macOS 15.0, *)
struct AddPasswordForm: View {
    var title: String = "Add New Password"
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.managedObjectContext) private var viewContext

    @Binding var serviceName: String
    @Binding var username: String
    @Binding var lgdata: String
    @Binding var website: String
    @Binding var phn: String
    @Binding var countryCode: String
    
    @State private var selectedCode: CountryCode = countryCodes.first!
    @Binding var passwordData: Data
    @Binding var passwordDisplay: String
    
    // NEW: Additional fields
    @State private var notes: String = ""
    @State private var isFavorite: Bool = false
    @State private var setPasswordExpiry: Bool = false
    @State private var expiryDate: Date = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var tags: [String] = []
    @State private var newTag: String = ""
    @State private var showAddTag: Bool = false
    
    var existingEntry: PasswordEntry?
    let selectedFolder: Folder?

    var onSave: (Data) -> Void
    var onCancel: () -> Void

    @State private var showPassword = false
    @State private var passwordStrength: String = ""
    @FocusState private var focusedField: Field?

    @State private var emailInlineSuggestion: String = ""
    @State private var websiteInlineSuggestion: String = ""
    @State private var serviceInlineSuggestion: String = ""
    @ObservedObject private var keyMonitor = KeyMonitor.shared
    @State private var confirmWeakPassword = false
    @State private var showPasswordGenerator = false
    @State private var showCategoryMismatchAlert = false
    
    // 2FA states
    @State private var showAddTOTP = false
    @State private var showRemoveTOTP = false
    
    @State private var resolvedFolderCategory: String? = nil
    @State private var folderNameCache: [NSManagedObjectID: String] = [:]
    
    //CLIPBOARD
    @AppStorage("clearDelay") private var clearDelay: Int = 10
    @State private var justCopiedPassword: Bool = false
        // Generate a temporary UUID for new entries (until they're saved)
    @State private var temporaryEntryID: UUID = UUID()
    
    // NEW: Password suggestions
    @State private var passwordSuggestions: [String] = []

    enum Field: Hashable { case service, username, password, lgdata, website, notes, newTag }
    
    @State private var category: String = "Other"

    private var existingCategories: [String] {
        let request: NSFetchRequest<PasswordEntry> = PasswordEntry.fetchRequest()
        request.propertiesToFetch = ["category"]
        request.resultType = .managedObjectResultType
        let results = (try? viewContext.fetch(request)) ?? []
        let names = Set(results.compactMap { ($0.category?.isEmpty == false) ? $0.category : nil })
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    // MARK: - Smart Folder Category Detection

    private func resolveFolderCategory() async -> String? {
        guard let folder = selectedFolder else { return nil }
        
        guard let secData = await CoreDataHelper.decryptedFolderName(folder) else {
            return nil
        }
        defer { secData.clear() }
        
        let folderName = secData.withUnsafeBytes { ptr -> String in
            guard let base = ptr.baseAddress else { return "" }
            let data = Data(bytes: base, count: ptr.count)
            return String(data: data, encoding: .utf8) ?? ""
        }.lowercased()
        
        // Check exact match in categoryMapping
        if let exactMatch = categoryMapping[folderName] {
            return exactMatch
        }
        
        // Check partial match in categoryMapping
        for (key, value) in categoryMapping {
            if folderName.contains(key) {
                return value
            }
        }
        
        // Check known categories
        let knownCategories = CategoryIcons.recommended + existingCategories
        if let matchedCategory = knownCategories.first(where: {
            $0.lowercased() == folderName
        }) {
            return matchedCategory
        }
        
        return nil
    }
    
    // isWiFiEntry
    private var isWiFiEntry: Bool {
        if let folderCat = resolvedFolderCategory, folderCat == "Wi-Fi" { return true }
        if category.lowercased().contains("wifi") || category.lowercased().contains("wi-fi") { return true }
        let s = serviceName.lowercased()
        return s.contains("ssid") || s.contains("wi-fi") || s.contains("wifi")
    }

    // shouldRestrictCategory
    private var shouldRestrictCategory: Bool {
        return resolvedFolderCategory != nil
    }

//MARK: - Custom list
    let serviceSuggestions = Domains.Domains
    let EmailDs = Domains.EmailDomains
    let websiteSuggestions = Domains.WebsiteDomain
//MARK: - END Custom list
    var body: some View {
        //ScrollView {
            VStack(spacing: 24) {
                // Header with smart icon
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(isWiFiEntry ? theme.badgeBackground.opacity(0.15) : theme.badgeBackground.opacity(0.15))
                            .frame(width: 64, height: 64)
                        
                        Image(systemName: isWiFiEntry ? "wifi" : (isFavorite ? "star.fill" : "key.fill"))
                            .font(.system(size: 28))
                            .foregroundStyle(theme.badgeBackground.gradient)
                    }
                    
                    Text(isWiFiEntry ? "Add Wi-Fi Network" : (existingEntry != nil ? "Edit Password" : title))
                        .font(.title2.weight(.semibold))
                        .foregroundColor(theme.primaryTextColor)
                    
                    // In the header section
                    if let folder = selectedFolder {
                        let folderName: String = {
                            guard let cached = folderNameCache[folder.objectID] else {
                                return "Folder"
                            }
                            return cached
                        }()
                        
                        Label("Saving to '\(folderName)' folder", systemImage: "folder.fill")
                            .font(.caption)
                            .foregroundColor(theme.badgeBackground)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(theme.badgeBackground.opacity(0.1))
                            .cornerRadius(8)
                    }

                    // folder restrictions info
                    if let restrictedCategory = resolvedFolderCategory {
                        Label("Category will be set to '\(restrictedCategory)'", systemImage: "info.circle.fill")
                            .font(.caption)
                            .foregroundColor(theme.badgeBackground)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(theme.badgeBackground.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                
                // Form fields
                VStack(spacing: 16) {
                    serviceField()
                    
                    if !isWiFiEntry {
                        usernameField()
                        emailField()
                        websiteField()
                        phoneField()
                    }
                    
                    passwordFieldSecure()
                    passwordStrengthView()
                    
                    // NEW: Password quality suggestions
                    if !passwordSuggestions.isEmpty {
                        passwordSuggestionsView()
                    }
                    
                    // 2FA Section
                    if !isWiFiEntry {
                        twoFactorSection()
                    }
                    
                    // NEW: Notes field
                    notesField()
                    
                    // NEW: Tags section
                    if !isWiFiEntry {
                        tagsSection()
                    }
                    
                    // NEW: Favorite and Expiry
                    additionalOptionsSection()
                }
                
                // Category picker
                if !isWiFiEntry || resolvedFolderCategory == nil {
                    categorySection
                }
                
                // Action buttons
                HStack(spacing: 12) {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    
                    Button("Save") {
                        Task {
                            await saveAction()
                        }
                    }

                        .buttonStyle(.borderedProminent)
                        .tint(theme.badgeBackground)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
        //}
        //.frame(maxWidth: 520, maxHeight: 850)
        .sheet(isPresented: $showAddTOTP) {
            if let entry = existingEntry {
                AddTOTPSecretView(entry: entry)
                    .environmentObject(theme)
                    .environment(\.managedObjectContext, viewContext)
            }
        }
        .sheet(isPresented: $showRemoveTOTP) {
            if let entry = existingEntry {
                RemoveTOTPView(entry: entry)
                    .environmentObject(theme)
                    .environment(\.managedObjectContext, viewContext)
            }
        }
        .alert("Weak Password", isPresented: $confirmWeakPassword) {
            Button("Cancel", role: .cancel) {}
            Button("Save Anyway", role: .destructive) { performSave() }
        } message: {
            Text("Your password is weak. Do you want to save it anyway?")
        }
        .alert("Category Mismatch", isPresented: $showCategoryMismatchAlert) {
            Button("Use '\(resolvedFolderCategory ?? "")'") {
                if let restrictedCategory = resolvedFolderCategory {
                    category = restrictedCategory
                }
            }
            Button("Change Anyway", role: .destructive) {
                performSave()
            }
        } message: {
            Text("You're adding to a folder which uses '\(resolvedFolderCategory ?? "")' category. Do you want to auto-correct the category?")
        }
        .onAppear {
            setupInitialState()
        }
        .appBackground()
    }

    // MARK: - NEW SECTIONS
    
    @ViewBuilder
    private func notesField() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notes (Optional)", systemImage: "note.text")
                .font(.subheadline.weight(.medium))
                .foregroundColor(theme.primaryTextColor)
            
            TextEditor(text: $notes)
                .frame(height: 80)
                .padding(8)
                .background(theme.isDarkBackground ? Color.white.opacity(0.05) : Color.gray.opacity(0.1))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.secondaryTextColor.opacity(0.2), lineWidth: 1)
                )
                .focused($focusedField, equals: .notes)
        }
        .padding(12)
        .background(theme.isDarkBackground ? Color.white.opacity(0.05) : Color.secondary.opacity(0.08))
        .cornerRadius(10)
    }
    
    @ViewBuilder
    private func tagsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Tags (Optional)", systemImage: "tag.fill")
                .font(.subheadline.weight(.medium))
                .foregroundColor(theme.primaryTextColor)
            
            // Display existing tags
            if !tags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        TagChip(tag: tag, theme: theme) {
                            withAnimation {
                                tags.removeAll { $0 == tag }
                            }
                        }
                    }
                }
            }
            
            // Add new tag
            HStack(spacing: 8) {
                if showAddTag {
                    HStack {
                        Image(systemName: "tag")
                            .foregroundColor(theme.secondaryTextColor)
                            .font(.caption)
                        
                        TextField("New tag", text: $newTag)
                            .textFieldStyle(.plain)
                            .focused($focusedField, equals: .newTag)
                            .onSubmit {
                                addTag()
                            }
                        
                        Button {
                            addTag()
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            withAnimation {
                                showAddTag = false
                                newTag = ""
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(theme.isDarkBackground ? Color.white.opacity(0.1) : Color.gray.opacity(0.15))
                    .cornerRadius(6)
                } else {
                    Button {
                        withAnimation {
                            showAddTag = true
                            focusedField = .newTag
                        }
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Tag")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                Spacer()
            }
        }
        .padding(12)
        .background(theme.isDarkBackground ? Color.white.opacity(0.05) : Color.secondary.opacity(0.08))
        .cornerRadius(10)
    }
    
    @ViewBuilder
    private func additionalOptionsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Favorite toggle
            Toggle(isOn: $isFavorite) {
                Label("Mark as Favorite", systemImage: isFavorite ? "star.fill" : "star")
                    .foregroundColor(theme.primaryTextColor)
            }
            .tint(theme.badgeBackground)
            
            Divider()
            
            // Password expiry
            Toggle(isOn: $setPasswordExpiry) {
                Label("Set Password Expiry Reminder", systemImage: "calendar.badge.clock")
                    .foregroundColor(theme.primaryTextColor)
            }
            .tint(theme.badgeBackground)
            
            if setPasswordExpiry {
                DatePicker("Expires on", selection: $expiryDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .padding(.leading, 28)
                
                HStack(spacing: 4) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption2)
                    Text("You'll be reminded to change this password")
                        .font(.caption2)
                }
                .foregroundColor(theme.secondaryTextColor)
                .padding(.leading, 28)
            }
        }
        .padding(12)
        .background(theme.isDarkBackground ? Color.white.opacity(0.05) : Color.secondary.opacity(0.08))
        .cornerRadius(10)
    }
    
    @ViewBuilder
    private func passwordSuggestionsView() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Password Suggestions", systemImage: "lightbulb.fill")
                .font(.caption.weight(.medium))
                .foregroundColor(.orange)
            
            ForEach(passwordSuggestions, id: \.self) { suggestion in
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text(suggestion)
                        .font(.caption)
                        .foregroundColor(theme.secondaryTextColor)
                }
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - 2FA Section
    
    @ViewBuilder
    private func twoFactorSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Two-Factor Authentication (Optional)", systemImage: "number.square.fill")
                .font(.subheadline.weight(.medium))
                .foregroundColor(theme.primaryTextColor)
            
            if let entry = existingEntry, entry.hasTwoFactor {
                // Show existing 2FA indicator
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    
                    Text("Authenticator configured")
                        .font(.caption)
                        .foregroundColor(theme.primaryTextColor)
                    
                    Spacer()
                    
                    Button("Update") {
                        showAddTOTP = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button("Remove") {
                        showRemoveTOTP = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                }
                .padding(12)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            } else {
                // Show add 2FA button
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        if existingEntry != nil {
                            showAddTOTP = true
                        }
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Authenticator")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(existingEntry == nil)
                    
                    if existingEntry == nil {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle.fill")
                                .font(.caption2)
                            Text("Save this entry first to add authenticator")
                                .font(.caption2)
                        }
                        .foregroundColor(.orange)
                    }
                }
            }
            
            Text("Works with services that support 2FA authenticator apps")
                .font(.caption2)
                .foregroundColor(theme.secondaryTextColor)
        }
        .padding(12)
        .background(theme.isDarkBackground ? Color.white.opacity(0.05) : Color.secondary.opacity(0.08))
        .cornerRadius(10)
    }

    // MARK: - Form Fields
    
    private func serviceField() -> some View {
        HStack(spacing: 8) {
            Image(systemName: isWiFiEntry ? "wifi" : "building.2.fill")
                .foregroundStyle(theme.badgeBackground.gradient)
                .frame(width: 24)

            ZStack(alignment: .leading) {
                TextField(
                    isWiFiEntry ? "Wi-Fi Name (SSID)" : "Service Name",
                    text: $serviceName
                )
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .service)
                .onChange(of: serviceName) { _ in
                    updateInlineServiceSuggestion(for: serviceName)
                }
                .onChange(of: keyMonitor.key) { key in
                    handleAutocomplete(key: key, field: .service)
                }

                if !serviceInlineSuggestion.isEmpty {
                    suggestionOverlay(current: serviceName, suggestion: serviceInlineSuggestion)
                }
            }
        }
    }
    
    private func usernameField() -> some View {
        HStack(spacing: 8) {
            Image(systemName: "person.fill")
                .foregroundColor(theme.secondaryTextColor)
                .frame(width: 24)
            
            TextField("Username", text: $username)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .username)
        }
    }

    private func emailField() -> some View {
        HStack(spacing: 8) {
            Image(systemName: "envelope.fill")
                .foregroundStyle(theme.badgeBackground)
                .frame(width: 24)

            ZStack(alignment: .leading) {
                TextField("Email", text: $lgdata)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .lgdata)
                    .onChange(of: lgdata) { _ in
                        updateInlineEmailSuggestion(for: lgdata)
                    }
                    .onChange(of: keyMonitor.key) { key in
                        handleAutocomplete(key: key, field: .lgdata)
                    }

                if !emailInlineSuggestion.isEmpty {
                    suggestionOverlay(current: lgdata, suggestion: emailInlineSuggestion)
                }
            }
        }
    }
    
    private func websiteField() -> some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .foregroundStyle(theme.badgeBackground)
                .frame(width: 24)

            ZStack(alignment: .leading) {
                TextField("Website", text: $website)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .website)
                    .onChange(of: website) { _ in
                        updateInlineWebsiteSuggestion(for: website)
                    }
                    .onChange(of: keyMonitor.key) { key in
                        handleAutocomplete(key: key, field: .website)
                    }

                if !websiteInlineSuggestion.isEmpty {
                    suggestionOverlay(current: website, suggestion: websiteInlineSuggestion)
                }
            }
        }
    }
    
    private func phoneField() -> some View {
        HStack(spacing: 8) {
            Image(systemName: "phone.fill")
                .foregroundStyle(theme.badgeBackground)
                .frame(width: 24)
            
            Picker(selection: $selectedCode, label: Text("")) {
                ForEach(countryCodes, id: \.id) { cc in
                    HStack {
                        Text(cc.flag)
                        Text(cc.code)
                        Text(cc.name)
                            .foregroundStyle(theme.primaryTextColor)
                    }
                    .tag(cc)
                }
            }
            .frame(width: 100)
            .pickerStyle(.menu)
            .labelsHidden()
            
            TextField("Phone Number", text: $phn)
                .textFieldStyle(.roundedBorder)
                .onChange(of: selectedCode) { newCode in
                    countryCode = newCode.code
                    if !phn.isEmpty && !phn.trimmingCharacters(in: .whitespaces).isEmpty {
                        let cleanedNumber = phn.removingCountryCodePrefix()
                        if !cleanedNumber.isEmpty {
                            phn = newCode.code + " " + cleanedNumber
                        }
                    }
                }
        }
    }

    private func passwordFieldSecure() -> some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(theme.badgeBackground)
                    .frame(width: 24)
                
                Group {
                    if showPassword {
                        TextField("Password", text: $passwordDisplay)
                            .onChange(of: passwordDisplay) { newValue in
                                passwordData = Data(newValue.utf8)
                                checkPasswordStrength()
                            }
                            .focused($focusedField, equals: .password)
                    } else {
                        SecureField("Password", text: $passwordDisplay)
                            .onChange(of: passwordDisplay) { newValue in
                                passwordData = Data(newValue.utf8)
                                checkPasswordStrength()
                            }
                            .focused($focusedField, equals: .password)
                    }
                }
                .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 8) {
                Button { showPassword.toggle() } label: {
                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                        .foregroundStyle(theme.badgeBackground.gradient)
                }
                .buttonStyle(.plain)
                
                Button { showPasswordGenerator.toggle() } label: {
                    Image(systemName: "sparkles")
                        .foregroundColor(theme.badgeBackground)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showPasswordGenerator) {
                    GeneratePasswordView(
                        passwordData: $passwordData,
                        passwordDisplay: $passwordDisplay
                    )
                }
                
                // ✅ UPDATED: Copy button with visual feedback
                Button {
                    copyPasswordToClipboard()
                } label: {
                    Image(systemName: justCopiedPassword ? "checkmark.circle.fill" : "doc.on.doc.fill")
                        .foregroundColor(justCopiedPassword ? .green : theme.badgeBackground)
                        .animation(.easeInOut(duration: 0.2), value: justCopiedPassword)
                }
                .buttonStyle(.plain)
                .help(justCopiedPassword ? "Copied!" : "Copy password")
            }
            .padding(.trailing, 12)
        }
    }
    
    // MARK: - Password Strength Check
    
    private func checkPasswordStrength() {
        guard let passwordString = String(data: passwordData, encoding: .utf8) else {
            passwordStrength = ""
            passwordSuggestions = []
            return
        }
        
        let length = passwordString.count
        let hasUpper = passwordString.rangeOfCharacter(from: .uppercaseLetters) != nil
        let hasLower = passwordString.rangeOfCharacter(from: .lowercaseLetters) != nil
        let hasNumber = passwordString.rangeOfCharacter(from: .decimalDigits) != nil
        let hasSpecial = passwordString.rangeOfCharacter(from: .punctuationCharacters) != nil

        var score = 0
        if length >= 12 { score += 1 }
        if hasUpper { score += 1 }
        if hasLower { score += 1 }
        if hasNumber { score += 1 }
        if hasSpecial { score += 1 }

        switch score {
        case 0...2: passwordStrength = "Weak"
        case 3...4: passwordStrength = "Medium"
        case 5: passwordStrength = "Strong"
        default: passwordStrength = ""
        }
        
        // Generate suggestions
        var suggestions: [String] = []
        if length < 12 {
            suggestions.append("Use at least 12 characters")
        }
        if !hasUpper {
            suggestions.append("Add uppercase letters (A-Z)")
        }
        if !hasLower {
            suggestions.append("Add lowercase letters (a-z)")
        }
        if !hasNumber {
            suggestions.append("Add numbers (0-9)")
        }
        if !hasSpecial {
            suggestions.append("Add special characters (!@#$%)")
        }
        
        passwordSuggestions = suggestions
    }
    
    private func copyPasswordToClipboard() {
        guard let passwordString = String(data: passwordData, encoding: .utf8) else { return }
        
        let entryID = existingEntry?.id ?? temporaryEntryID
        
        Task { @MainActor in
            await SecureClipboard.shared.copy(
                text: passwordString,
                entryID: entryID,
                clearAfter: TimeInterval(max(1, clearDelay))
            )
            
            justCopiedPassword = true
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            justCopiedPassword = false
        }
    }
    
    private func passwordStrengthView() -> some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(theme.isDarkBackground ? Color.white.opacity(0.1) : Color.gray.opacity(0.2))
                        .frame(height: 6)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(passwordStrengthColor())
                        .frame(width: strengthBarWidth(totalWidth: geo.size.width), height: 6)
                        .animation(.easeInOut(duration: 0.3), value: passwordStrength)
                }
            }
            .frame(height: 6)
            
            if !passwordStrength.isEmpty {
                HStack {
                    Text("Strength:")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryTextColor)
                    Text(passwordStrength)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(passwordStrengthColor())
                    Spacer()
                }
            }
        }
    }
    
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Category", systemImage: "tag.fill")
                .font(.subheadline.weight(.medium))
                .foregroundColor(theme.primaryTextColor)
            
            HStack(spacing: 8) {
                Picker("Category", selection: $category) {
                    let categories = existingCategories.contains("Other") ? existingCategories : ["Other"] + existingCategories
                    ForEach(categories, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
                .disabled(shouldRestrictCategory && existingEntry == nil)
                
                Menu {
                    Section("Recommended") {
                        ForEach(CategoryIcons.recommended, id: \.self) { name in
                            Button {
                                category = name
                            } label: {
                                Label(name, systemImage: CategoryIcons.icon(for: name))
                            }
                        }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .buttonStyle(.bordered)
                .disabled(shouldRestrictCategory && existingEntry == nil)
            }
            
            if shouldRestrictCategory, let restrictedCategory = resolvedFolderCategory {
                HStack(spacing: 6) {
                    Image(systemName: category == restrictedCategory ? "checkmark.circle.fill" : "info.circle.fill")
                        .foregroundColor(category == restrictedCategory ? .green : .orange)
                    
                    Text(category == restrictedCategory ?
                         "Category matches folder" :
                         "Category will be set to '\(restrictedCategory)'")
                        .font(.caption)
                        .foregroundColor(category == restrictedCategory ? .green : .orange)
                }
            }
        }
        .padding(12)
        .background(theme.isDarkBackground ? Color.white.opacity(0.05) : Color.secondary.opacity(0.08))
        .cornerRadius(10)
    }

    private func suggestionOverlay(current: String, suggestion: String) -> some View {
        HStack(spacing: 0) {
            Text(current).opacity(0)
            Text(suggestion.dropFirst(current.count))
                .foregroundColor(theme.tertiaryTextColor)
            Spacer()
        }
        .allowsHitTesting(false)
        .padding(.leading, 10)
    }

    // MARK: - Helper Functions
    
    private func addTag() {
        let trimmedTag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTag.isEmpty else { return }
        guard !tags.contains(trimmedTag) else {
            newTag = ""
            return
        }
        
        withAnimation {
            tags.append(trimmedTag)
            newTag = ""
            showAddTag = false
        }
    }

    private func setupInitialState() {
        if existingEntry == nil {
            temporaryEntryID = UUID()
        }
        
        if let existingPrefix = countryCodes.first(where: { phn.hasPrefix($0.code) }) {
            selectedCode = existingPrefix
            countryCode = existingPrefix.code
        } else {
            selectedCode = countryCodes.first!
            countryCode = selectedCode.code
        }
        
        if let entry = existingEntry {
            serviceName = entry.serviceName ?? ""
            username = entry.username ?? ""
            lgdata = entry.lgdata ?? ""
            phn = entry.phn ?? ""
            website = entry.website ?? ""
            category = entry.category ?? "Other"
            notes = entry.notes ?? ""
            isFavorite = entry.isFavorite
            
            if let expiry = entry.passwordExpiry {
                setPasswordExpiry = true
                expiryDate = expiry
            }
            
            if let tagsString = entry.tags {
                tags = tagsString.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        } else {
            // Resolve folder category asynchronously
            Task {
                resolvedFolderCategory = await resolveFolderCategory()
                if let restrictedCategory = resolvedFolderCategory {
                    category = restrictedCategory
                }
            }
        }
        
        focusedField = .service
    }
    
    private func updateInlineServiceSuggestion(for input: String) {
        guard !input.isEmpty else {
            serviceInlineSuggestion = ""
            return
        }

        if let match = serviceSuggestions.first(where: {
            $0.lowercased().hasPrefix(input.lowercased())
        }) {
            serviceInlineSuggestion = match
        } else {
            serviceInlineSuggestion = ""
        }
    }
    
    private func updateInlineEmailSuggestion(for input: String) {
        guard !input.isEmpty else {
            emailInlineSuggestion = ""
            return
        }

        if let atIndex = input.firstIndex(of: "@") {
            let prefix = String(input[..<atIndex])
            let domainPart = String(input[input.index(after: atIndex)...])
            if let match = EmailDs.first(where: { $0.hasPrefix(domainPart.lowercased()) }) {
                emailInlineSuggestion = prefix + "@" + match
            } else {
                emailInlineSuggestion = ""
            }
        } else {
            emailInlineSuggestion = input + "@gmail.com"
        }
    }
    
    private func updateInlineWebsiteSuggestion(for input: String) {
        guard !input.isEmpty else {
            websiteInlineSuggestion = ""
            return
        }
        
        guard !input.contains(".") else {
            websiteInlineSuggestion = ""
            return
        }
        
        if let match = websiteSuggestions.first(where: {
            $0.hasPrefix(input.lowercased())
        }) {
            websiteInlineSuggestion = match
        } else {
            websiteInlineSuggestion = input + ".com"
        }
    }
    
    private func handleAutocomplete(key: UInt16?, field: Field) {
        guard let key = key else { return }
        
        switch key {
        case 48, 124, 36:
            switch field {
            case .service:
                if !serviceInlineSuggestion.isEmpty {
                    serviceName = serviceInlineSuggestion
                    serviceInlineSuggestion = ""
                }
            case .lgdata:
                if !emailInlineSuggestion.isEmpty {
                    lgdata = emailInlineSuggestion
                    emailInlineSuggestion = ""
                }
            case .website:
                if !websiteInlineSuggestion.isEmpty {
                    website = websiteInlineSuggestion
                    websiteInlineSuggestion = ""
                }
            default:
                break
            }
        case 53:
            serviceInlineSuggestion = ""
            emailInlineSuggestion = ""
            websiteInlineSuggestion = ""
        default:
            break
        }
    }

    private func passwordStrengthColor() -> Color {
        switch passwordStrength {
        case "Weak": return .red
        case "Medium": return .orange
        case "Strong": return .green
        default: return .gray
        }
    }

    private func strengthBarWidth(totalWidth: CGFloat) -> CGFloat {
        switch passwordStrength {
        case "Weak": return totalWidth * 0.33
        case "Medium": return totalWidth * 0.66
        case "Strong": return totalWidth
        default: return 0
        }
    }

    private func saveAction() async {
        guard await SecureKeyStorage.shared.hasKey() else {
            print("Cannot save: master password not unlocked")
            return
        }
        
        guard !serviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !passwordData.isEmpty else { return }
        
        if existingEntry == nil, let restrictedCategory = resolvedFolderCategory, category != restrictedCategory {
            showCategoryMismatchAlert = true
            return
        }

        if passwordStrength == "Weak" {
            confirmWeakPassword = true
            return
        }

        performSave()
    }

    private func performSave() {
        Task {
            guard await SecureKeyStorage.shared.hasKey() else {
                print("Cannot save: master password not unlocked")
                return
            }

            guard !serviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            guard !passwordData.isEmpty else { return }

            if existingEntry == nil,
               let restrictedCategory = resolvedFolderCategory,
               category != restrictedCategory
            {
                showCategoryMismatchAlert = true
                return
            }

            if passwordStrength == "Weak" {
                confirmWeakPassword = true
                return
            }

            performActualSave()
        }
    }

    
    private func performActualSave() {
        Task {
            guard await SecureKeyStorage.shared.hasKey() else {
                print("Cannot save: master password not unlocked")
                return
            }
            
            guard !serviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            guard !passwordData.isEmpty else { return }
            
            let secureStorage = SecurePasswordStorage()
            secureStorage.set(passwordData)
            
            defer {
                secureStorage.clear()
                passwordData.secureWipe()
                passwordDisplay = ""
            }
            
            // Apply folder category restriction
            if existingEntry == nil, let restrictedCategory = resolvedFolderCategory {
                category = restrictedCategory
            }
            
            if isWiFiEntry && category != "Wi-Fi" {
                category = "Wi-Fi"
            }
            
            guard let secureData = secureStorage.get() else { return }
            
            let context = PersistenceController.shared.container.viewContext
            let tagsString = tags.isEmpty ? nil : tags.joined(separator: ",")
            
            if let editingEntry = existingEntry {
                await CoreDataHelper.upsertPassword(
                    entry: editingEntry,
                    serviceName: serviceName,
                    username: username,
                    lgdata: lgdata.isEmpty ? nil : lgdata,
                    countryCode: countryCode,
                    phn: phn,
                    website: website,
                    passwordData: secureData,
                    category: category,
                    folder: selectedFolder,
                    notes: notes.isEmpty ? nil : notes,
                    isFavorite: isFavorite,
                    passwordExpiry: setPasswordExpiry ? expiryDate : nil,
                    tags: tagsString,
                    context: context
                )
            } else {
                await CoreDataHelper.savePassword(
                    serviceName: serviceName,
                    username: username,
                    lgdata: lgdata.isEmpty ? nil : lgdata,
                    countryCode: countryCode,
                    phn: phn,
                    website: website,
                    passwordData: secureData,
                    category: category,
                    folder: selectedFolder,
                    notes: notes.isEmpty ? nil : notes,
                    isFavorite: isFavorite,
                    passwordExpiry: setPasswordExpiry ? expiryDate : nil,
                    tags: tagsString,
                    context: context
                )
            }
            
            // Clear form
            serviceName = ""
            username = ""
            lgdata = ""
            phn = ""
            website = ""
            notes = ""
            tags = []
            isFavorite = false
            setPasswordExpiry = false
            resolvedFolderCategory = nil
            
            onCancel()
        }
    }
    
    private func copyToClipboard_FINAL(_ text: String) {
        let entryID = existingEntry?.id ?? temporaryEntryID
        
        Task { @MainActor in
            await SecureClipboard.shared.copy(
                text: text,
                entryID: entryID,
                clearAfter: TimeInterval(max(1, clearDelay))
            )
        }
    }
}

// MARK: - Supporting Views

struct TagChip: View {
    let tag: String
    let theme: ThemeManager
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            Text(tag)
                .font(.caption)
                .foregroundColor(theme.primaryTextColor)
            
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(theme.secondaryTextColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(theme.badgeBackground.opacity(0.2))
        .cornerRadius(12)
    }
}



private extension String {
    func removingCountryCodePrefix() -> String {
        let codes = countryCodes.map { $0.code }
        for code in codes where self.hasPrefix(code) {
            let trimmed = self.dropFirst(code.count).trimmingCharacters(in: .whitespaces)
            return String(trimmed)
        }
        return self
    }
}

