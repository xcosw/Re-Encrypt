import SwiftUI
import CoreData

struct PasswordListView: View {
    @Environment(\.managedObjectContext) private var viewcContext
    var onDelete: (PasswordEntry) -> Void
    @EnvironmentObject private var theme: ThemeManager
    
    // Inputs from parent
    @Binding var selectedPassword: PasswordEntry?
    @Binding var folderMode: FolderMode
    @Binding var selectedFolderID: NSManagedObjectID?
    @Binding var searchText: String
    @Binding var selectedCategory: String
    @Binding var useGrid: Bool

    // Local UI state
    @State private var hoveredID: NSManagedObjectID? = nil
    @State private var showDeleteConfirm: PasswordEntry? = nil
    @State private var copiedField: String? = nil
    @State private var sortOption: SortOption = .dateNewest
    @State private var showSortMenu = false
    
    // Security: Auto-clear clipboard
    @AppStorage("autoClearClipboard") private var autoClearClipboard: Bool = true
    @AppStorage("clearDelay") private var clearDelay: Int = 10
    @State private var clipboardTimer: Timer?

    @FetchRequest private var passwords: FetchedResults<PasswordEntry>
    
    enum SortOption: String, CaseIterable {
        case dateNewest = "Newest First"
        case dateOldest = "Oldest First"
        case nameAZ = "Name (A-Z)"
        case nameZA = "Name (Z-A)"
        
        var descriptor: NSSortDescriptor {
            switch self {
            case .dateNewest: return NSSortDescriptor(key: "createdAt", ascending: false)
            case .dateOldest: return NSSortDescriptor(key: "createdAt", ascending: true)
            case .nameAZ: return NSSortDescriptor(key: "serviceName", ascending: true, selector: #selector(NSString.caseInsensitiveCompare(_:)))
            case .nameZA: return NSSortDescriptor(key: "serviceName", ascending: false, selector: #selector(NSString.caseInsensitiveCompare(_:)))
            }
        }
    }

    private var dynamicCategories: [(name: String, icon: String)] {
        let names = Set(passwords.compactMap { ($0.category?.isEmpty == false) ? $0.category : nil })
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let mapped: [(name: String, icon: String)] = names.map { cat in
            (cat, CategoryIcons.icon(for: cat))
        }
        let all = ("All", CategoryIcons.icon(for: "All"))
        let hasNoCategory = passwords.contains { ($0.category ?? "").isEmpty }
        let noCatTuple: (name: String, icon: String)? = hasNoCategory ? (Self.noCategoryDisplayName, CategoryIcons.icon(for: "Other")) : nil
        return [all] + mapped + (noCatTuple.map { [$0] } ?? [])
    }

    let brandColors: [String: Color] = [
        // Core Tech Giants
        "Google": Color(red: 66/255, green: 133/255, blue: 244/255),
        "Gmail": Color(red: 234/255, green: 67/255, blue: 53/255),
        "Facebook": Color(red: 24/255, green: 119/255, blue: 242/255),
        "Apple": Color(red: 0/255, green: 0/255, blue: 0/255),
        "GitHub": Color(red: 36/255, green: 41/255, blue: 47/255),
        "Twitter": Color(red: 29/255, green: 161/255, blue: 242/255),
        "Instagram": Color(red: 131/255, green: 58/255, blue: 180/255),
        "LinkedIn": Color(red: 10/255, green: 102/255, blue: 194/255),
        "Slack": Color(red: 74/255, green: 21/255, blue: 75/255),
        "Reddit": Color(red: 255/255, green: 69/255, blue: 0/255),
        "Dropbox": Color(red: 0/255, green: 97/255, blue: 255/255),
        "Microsoft": Color(red: 242/255, green: 80/255, blue: 34/255),
        "Zoom": Color(red: 0/255, green: 112/255, blue: 255/255),
        "Amazon": Color(red: 255/255, green: 153/255, blue: 0/255),
        "Netflix": Color(red: 229/255, green: 9/255, blue: 20/255),
        "Spotify": Color(red: 30/255, green: 215/255, blue: 96/255),
        "Pinterest": Color(red: 189/255, green: 8/255, blue: 28/255),
        "Trello": Color(red: 0/255, green: 121/255, blue: 191/255),
        "Asana": Color(red: 246/255, green: 114/255, blue: 95/255),
        "Yahoo": Color(red: 67/255, green: 2/255, blue: 151/255),
        "ProtonMail": Color(red: 88/255, green: 75/255, blue: 141/255),
        "Discord": Color(red: 88/255, green: 101/255, blue: 242/255),
        "TikTok": Color(red: 0/255, green: 242/255, blue: 234/255),
        "WhatsApp": Color(red: 37/255, green: 211/255, blue: 102/255),
        "Snapchat": Color(red: 255/255, green: 252/255, blue: 0/255),
        "Figma": Color(red: 242/255, green: 78/255, blue: 30/255),
        "Notion": Color(red: 0/255, green: 0/255, blue: 0/255),
        "Bitbucket": Color(red: 38/255, green: 132/255, blue: 255/255),
        "Medium": Color(red: 0/255, green: 0/255, blue: 0/255),
        "StackOverflow": Color(red: 244/255, green: 128/255, blue: 36/255),
        "WordPress": Color(red: 33/255, green: 117/255, blue: 155/255),
        "Salesforce": Color(red: 0/255, green: 161/255, blue: 224/255),
        "PayPal": Color(red: 0/255, green: 48/255, blue: 135/255),
        "Venmo": Color(red: 10/255, green: 132/255, blue: 255/255),
        "Square": Color(red: 0/255, green: 0/255, blue: 0/255),
        "Stripe": Color(red: 99/255, green: 91/255, blue: 255/255),
        "Shopify": Color(red: 0/255, green: 128/255, blue: 96/255),
        "Evernote": Color(red: 30/255, green: 185/255, blue: 95/255),
        "OneDrive": Color(red: 0/255, green: 114/255, blue: 198/255),
        "Google Drive": Color(red: 60/255, green: 186/255, blue: 84/255),
        "Microsoft Teams": Color(red: 104/255, green: 33/255, blue: 122/255),
        "YouTube": Color(red: 255/255, green: 0/255, blue: 0/255),
        "Twitch": Color(red: 145/255, green: 70/255, blue: 255/255),
        "SoundCloud": Color(red: 255/255, green: 85/255, blue: 0/255),
        "Telegram": Color(red: 0/255, green: 136/255, blue: 204/255),
        "Signal": Color(red: 66/255, green: 133/255, blue: 244/255),

        // Security / VPN / Privacy
        "ProtonVPN": Color(red: 0/255, green: 128/255, blue: 255/255),
        "NordVPN": Color(red: 0/255, green: 82/255, blue: 204/255),
        "ExpressVPN": Color(red: 207/255, green: 15/255, blue: 28/255),
        "DuckDuckGo": Color(red: 255/255, green: 109/255, blue: 33/255),
        "1Password": Color(red: 0/255, green: 122/255, blue: 255/255),
        "LastPass": Color(red: 204/255, green: 0/255, blue: 0/255),
        "Bitwarden": Color(red: 0/255, green: 82/255, blue: 204/255),
        "Keeper": Color(red: 255/255, green: 187/255, blue: 0/255),
        "ProtonCalendar": Color(red: 100/255, green: 70/255, blue: 160/255),
        "ProtonContacts": Color(red: 92/255, green: 70/255, blue: 150/255),
        "Proton Wiki": Color(red: 82/255, green: 65/255, blue: 135/255),

        // Creative / Design
        "Canva": Color(red: 0/255, green: 171/255, blue: 165/255),
        "Behance": Color(red: 19/255, green: 20/255, blue: 24/255),
        "Dribbble": Color(red: 234/255, green: 76/255, blue: 137/255),
        "OpenAI": Color(red: 26/255, green: 26/255, blue: 26/255),
        "ChatGPT": Color(red: 0/255, green: 180/255, blue: 150/255),
        "Adobe": Color(red: 255/255, green: 0/255, blue: 0/255),

        // Productivity / Scheduling
        "Calendly": Color(red: 0/255, green: 145/255, blue: 234/255),
        "ZoomInfo": Color(red: 214/255, green: 0/255, blue: 28/255),
        "Fiverr": Color(red: 0/255, green: 184/255, blue: 122/255),
        "Upwork": Color(red: 91/255, green: 189/255, blue: 114/255),
        "Coursera": Color(red: 0/255, green: 73/255, blue: 164/255),
        "Udemy": Color(red: 255/255, green: 0/255, blue: 85/255),
        "Khan Academy": Color(red: 22/255, green: 121/255, blue: 107/255),
        "Duolingo": Color(red: 120/255, green: 200/255, blue: 80/255),

        // Streaming / Entertainment
        "Disney+": Color(red: 0/255, green: 66/255, blue: 150/255),
        "HBO Max": Color(red: 95/255, green: 0/255, blue: 157/255),
        "Hulu": Color(red: 28/255, green: 231/255, blue: 131/255),
        "Vimeo": Color(red: 26/255, green: 183/255, blue: 234/255),
        "Soundtrap": Color(red: 103/255, green: 58/255, blue: 183/255),
        "TripAdvisor": Color(red: 0/255, green: 175/255, blue: 137/255),
        "Airbnb": Color(red: 255/255, green: 90/255, blue: 95/255),
        "Booking.com": Color(red: 0/255, green: 53/255, blue: 128/255),
        "Expedia": Color(red: 255/255, green: 216/255, blue: 0/255),

        // Education / AI Tools
        "Udacity": Color(red: 1/255, green: 180/255, blue: 228/255),
        "DataCamp": Color(red: 0/255, green: 207/255, blue: 158/255),
        "DeepL": Color(red: 0/255, green: 70/255, blue: 130/255),
        "Grammarly": Color(red: 0/255, green: 179/255, blue: 152/255),
        "Reverso": Color(red: 0/255, green: 114/255, blue: 206/255),
        "Wordtune": Color(red: 156/255, green: 39/255, blue: 176/255),
        "Copy.ai": Color(red: 94/255, green: 117/255, blue: 255/255),
        "Jasper": Color(red: 130/255, green: 60/255, blue: 255/255),

        // Focus / Wellbeing
        "Calm": Color(red: 43/255, green: 118/255, blue: 210/255),
        "Headspace": Color(red: 255/255, green: 112/255, blue: 40/255),
        "Focus@Will": Color(red: 237/255, green: 85/255, blue: 59/255),
        "MyNoise": Color(red: 105/255, green: 105/255, blue: 105/255)
    ]
    init(
        onDelete: @escaping (PasswordEntry) -> Void,
        selectedPassword: Binding<PasswordEntry?>,
        folderMode: Binding<FolderMode>,
        selectedFolderID: Binding<NSManagedObjectID?>,
        searchText: Binding<String>,
        selectedCategory: Binding<String>,
        useGrid: Binding<Bool>
    ) {
        self.onDelete = onDelete
        self._selectedPassword = selectedPassword
        self._folderMode = folderMode
        self._selectedFolderID = selectedFolderID
        self._searchText = searchText
        self._selectedCategory = selectedCategory
        self._useGrid = useGrid

        let sort = [NSSortDescriptor(key: "createdAt", ascending: false)]
        let predicate = PasswordListView.buildPredicate(
            folderMode: folderMode.wrappedValue,
            selectedFolderID: selectedFolderID.wrappedValue,
            searchText: searchText.wrappedValue,
            selectedCategory: selectedCategory.wrappedValue
        )
        _passwords = FetchRequest(
            entity: PasswordEntry.entity(),
            sortDescriptors: sort,
            predicate: predicate,
            animation: .default
        )
    }

   /* private static func buildPredicate(
        folderMode: FolderMode,
        selectedFolderID: NSManagedObjectID?,
        searchText: String,
        selectedCategory: String
    ) -> NSPredicate? {
        var subpredicates: [NSPredicate] = []

        switch folderMode {
        case .all: break
        case .unfiled:
            subpredicates.append(NSPredicate(format: "folder == nil"))
        case .specific:
            if let id = selectedFolderID {
                    subpredicates.append(NSPredicate(format: "folder == %@", id))  // ← This should work
                } else {
                subpredicates.append(NSPredicate(value: false))
            }
        case .favorites:if let id = selectedFolderID {
            subpredicates.append(NSPredicate(format: "folder == %@", id))  // ← This should work
        } else {
        subpredicates.append(NSPredicate(value: false))
    }
        case .twoFactor: if let id = selectedFolderID {
            subpredicates.append(NSPredicate(format: "folder == %@", id))  // ← This should work
        } else {
        subpredicates.append(NSPredicate(value: false))
    }
        }
    

        if !searchText.isEmpty {
            let like = searchText
            let p1 = NSPredicate(format: "serviceName CONTAINS[cd] %@", like)
            let p2 = NSPredicate(format: "username CONTAINS[cd] %@", like)
            let p3 = NSPredicate(format: "lgdata CONTAINS[cd] %@", like)
            subpredicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: [p1, p2, p3]))
        }

        if selectedCategory != "All" {
            if selectedCategory == noCategoryDisplayName {
                let pNil = NSPredicate(format: "category == nil")
                let pEmpty = NSPredicate(format: "category == %@", "")
                subpredicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: [pNil, pEmpty]))
            } else {
                subpredicates.append(NSPredicate(format: "category == %@", selectedCategory))
            }
        }

        if subpredicates.isEmpty { return nil }
        return NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)
    }*/
    
    private static func buildPredicate(
        folderMode: FolderMode,
        selectedFolderID: NSManagedObjectID?,
        searchText: String,
        selectedCategory: String
    ) -> NSPredicate? {
        var subpredicates: [NSPredicate] = []

        // FIXED: Proper predicates for each mode
        switch folderMode {
        case .all:
            break // Show all passwords
            
        case .unfiled:
            subpredicates.append(NSPredicate(format: "folder == nil"))
            
        case .favorites:
            // ✅ FIXED: Show only favorites
            subpredicates.append(NSPredicate(format: "isFavorite == YES"))
            
        case .twoFactor:
            // ✅ FIXED: Show only passwords with 2FA
            subpredicates.append(NSPredicate(format: "encryptedTOTPSecret != nil AND totpSalt != nil"))
            
        case .specific:
            if let id = selectedFolderID {
                subpredicates.append(NSPredicate(format: "folder == %@", id))
            } else {
                subpredicates.append(NSPredicate(value: false))
            }
        }

        // Search filter
        if !searchText.isEmpty {
            let like = searchText
            let p1 = NSPredicate(format: "serviceName CONTAINS[cd] %@", like)
            let p2 = NSPredicate(format: "username CONTAINS[cd] %@", like)
            let p3 = NSPredicate(format: "lgdata CONTAINS[cd] %@", like)
            subpredicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: [p1, p2, p3]))
        }

        // Category filter
        if selectedCategory != "All" {
            if selectedCategory == noCategoryDisplayName {
                let pNil = NSPredicate(format: "category == nil")
                let pEmpty = NSPredicate(format: "category == %@", "")
                subpredicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: [pNil, pEmpty]))
            } else {
                subpredicates.append(NSPredicate(format: "category == %@", selectedCategory))
            }
        }

        if subpredicates.isEmpty { return nil }
        return NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)
    }

  /*  private var fetchKey: String {
        let folderKey: String
        switch folderMode {
        case .all: folderKey = "all"
        case .unfiled: folderKey = "unfiled"
        case .specific: folderKey = selectedFolderID?.uriRepresentation().absoluteString ?? "none"
        case .favorites: folderKey = "favorites"
        case .twoFactor: folderKey = "twoFactor"
        }
        
        return [folderKey, searchText, selectedCategory].joined(separator: "|")
    }

    private var currentFolderKey: String {
        switch folderMode {
        case .all: return "all"
        case .unfiled: return "unfiled"
        case .favorites: return "favorites"
        case .twoFactor: return "twoFactor"
        case .specific: return selectedFolderID?.uriRepresentation().absoluteString ?? "none"
        }
    }*/
    
    private var fetchKey: String {
        let folderKey: String
        switch folderMode {
        case .all: folderKey = "all"
        case .unfiled: folderKey = "unfiled"
        case .favorites: folderKey = "favorites"
        case .twoFactor: folderKey = "twoFactor"
        case .specific: folderKey = selectedFolderID?.uriRepresentation().absoluteString ?? "none"
        }
        
        return [folderKey, searchText, selectedCategory].joined(separator: "|")
    }

    private var currentFolderKey: String {
        switch folderMode {
        case .all: return "all"
        case .unfiled: return "unfiled"
        case .favorites: return "favorites"
        case .twoFactor: return "twoFactor"
        case .specific: return selectedFolderID?.uriRepresentation().absoluteString ?? "none"
        }
    }
    
    // Sorted passwords based on current sort option
    private var sortedPasswords: [PasswordEntry] {
        passwords.sorted { entry1, entry2 in
            switch sortOption {
            case .dateNewest:
                return (entry1.createdAt ?? Date()) > (entry2.createdAt ?? Date())
            case .dateOldest:
                return (entry1.createdAt ?? Date()) < (entry2.createdAt ?? Date())
            case .nameAZ:
                return (entry1.serviceName ?? "").localizedCaseInsensitiveCompare(entry2.serviceName ?? "") == .orderedAscending
            case .nameZA:
                return (entry1.serviceName ?? "").localizedCaseInsensitiveCompare(entry2.serviceName ?? "") == .orderedDescending
            }
        }
    }

    
   /* private var folderHasRestrictedCategory: Bool {
        // Check if we're in a specific folder view
        guard case .specific = folderMode else { return false }
        
        // Get the current folder
        guard let folderID = selectedFolderID else { return false }
        
        // You'd need to fetch the folder to check its name
        // For now, we'll check if the folder name matches a known category
        let request: NSFetchRequest<Folder> = Folder.fetchRequest()
        request.predicate = NSPredicate(format: "self == %@", folderID)
        
        do {
            if let folder = try viewcContext.fetch(request).first {
                let folderName = CoreDataHelper.decryptedFolderName(folder)?.lowercased() ?? ""
                
                // List of known categories that map to folders
                let restrictedCategories = ["wi-fi", "wifi", "social", "work", "finance", "personal",
                                           "gaming", "shopping", "email", "banking", "entertainment",
                                           "education", "health", "travel", "streaming"]
                
                return restrictedCategories.contains { folderName.contains($0) } ||
                       restrictedCategories.contains(folderName)
            }
        } catch {
            return false
        }
        
        return false
    }*/
    
    private var folderHasRestrictedCategory: Bool {
        // Never hide category chips for special modes
        switch folderMode {
        case .all, .unfiled, .favorites, .twoFactor:
            return false
        case .specific:
            break
        }
        
        // Check if we're in a specific folder view
        guard let folderID = selectedFolderID else { return false }
        
        // Fetch the folder to check its name
        let request: NSFetchRequest<Folder> = Folder.fetchRequest()
        request.predicate = NSPredicate(format: "self == %@", folderID)
        
        do {
            if let folder = try viewcContext.fetch(request).first {
                let folderName = CoreDataHelper.decryptedFolderName(folder)?.lowercased() ?? ""
                
                // List of known categories that map to folders
                let restrictedCategories = ["wi-fi", "wifi", "social", "work", "finance", "personal",
                                           "gaming", "shopping", "email", "banking", "entertainment",
                                           "education", "health", "travel", "streaming"]
                
                return restrictedCategories.contains { folderName.contains($0) } ||
                       restrictedCategories.contains(folderName)
            }
        } catch {
            return false
        }
        
        return false
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Enhanced toolbar with sort and count
            toolbarSection
            
            // Only show category chips if NOT in a folder with restricted category
                    if !folderHasRestrictedCategory {
                        categoryChipsBar()
                        Divider()
                    }
            
            Divider()

            // Empty state or content
            if passwords.isEmpty {
                emptyStateView
            } else {
                Group {
                    if useGrid {
                        gridView
                    } else {
                        listView
                    }
                }
            }
        }
        .onChange(of: dynamicCategories.map(\.name)) { _ in
            if !dynamicCategories.map(\.name).contains(selectedCategory) {
                selectedCategory = "All"
            }
        }
        .id(fetchKey)
        .animation(.easeInOut, value: useGrid)
        .onAppear {
            if let saved = LayoutPreferenceStore.shared.layoutMode(for: currentFolderKey) {
                useGrid = (saved == .grid)
            }
        }
        .onChange(of: currentFolderKey) { _ in
            if let saved = LayoutPreferenceStore.shared.layoutMode(for: currentFolderKey) {
                useGrid = (saved == .grid)
            }
        }
        .onChange(of: useGrid) { newValue in
            LayoutPreferenceStore.shared.setLayoutMode(newValue ? .grid : .list, for: currentFolderKey)
        }
        .alert("Delete Password?", isPresented: Binding(
            get: { showDeleteConfirm != nil },
            set: { if !$0 { showDeleteConfirm = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let entry = showDeleteConfirm {
                    withAnimation {
                        onDelete(entry)
                    }
                }
                showDeleteConfirm = nil
            }
            Button("Cancel", role: .cancel) {
                showDeleteConfirm = nil
            }
        } message: {
            if let entry = showDeleteConfirm {
                Text("Are you sure you want to delete '\(entry.serviceName ?? "this password")'? This action cannot be undone.")
            }
        }
        .appBackground()
    }
    
    // MARK: - Toolbar Section
    
    private var toolbarSection: some View {
        HStack(spacing: 12) {
            // Count badge
            HStack(spacing: 6) {
                Image(systemName: "key.fill")
                    .font(.caption)
                    .tint(theme.badgeBackground)
                Text("\(passwords.count)")
                    .font(.caption.bold())
                    .foregroundStyle(theme.primaryTextColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.secondary.opacity(0.1)))
            
            Spacer()
            
            // Sort menu
            Menu {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Button {
                        sortOption = option
                    } label: {
                        HStack {
                            Text(option.rawValue)
                            if sortOption == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption)
                    Text("Sort")
                        .font(.caption)
                }
                .tint(theme.badgeBackground)    
            }
            .menuStyle(.borderlessButton)
            .help("Sort passwords")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "lock.slash")
                    .font(.system(size: 36))
                    .foregroundStyle(theme.primaryTextColor)
            }
            
            VStack(spacing: 6) {
                Text("No Passwords")
                    .font(.headline)
                    .foregroundStyle(theme.primaryTextColor)
                
                Text(searchText.isEmpty ? "Add your first password to get started" : "No passwords match your search")
                    .font(.subheadline)
                    .foregroundStyle(theme.primaryTextColor)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Grid View
    
    private var gridView: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                ForEach(sortedPasswords, id: \.objectID) { entry in
                    passwordTile(entry)
                        .contextMenu { rowContextMenu(for: entry) }
                }
            }
            .padding(12)
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedPassword = nil }
    }
    
    // MARK: - List View
    
    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(sortedPasswords, id: \.objectID) { entry in
                    passwordRow(entry)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedPassword = (selectedPassword == entry ? nil : entry)
                            }
                        }
                        .contextMenu { rowContextMenu(for: entry) }
                }
            }
            .padding(12)
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedPassword = nil }
    }

    // MARK: - Category Chips
    
    @ViewBuilder
    private func categoryChipsBar() -> some View {
        GeometryReader { geo in
            let allCats = dynamicCategories
            let paddingPerChip: CGFloat = 8
            let chipHeight: CGFloat = 26

            let font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
            let chipWidths: [CGFloat] = allCats.map { cat in
                let text = cat.name as NSString
                let textWidth = text.size(withAttributes: [.font: font]).width
                return 16 + 6 + textWidth + paddingPerChip * 2
            }

            let (visibleIndices, overflowIndices) = computeChipLayout(
                chipWidths: chipWidths,
                availableWidth: geo.size.width
            )

            HStack(spacing: 6) {
                ForEach(visibleIndices, id: \.self) { idx in
                    let cat = allCats[idx]
                    chipView(name: cat.name, icon: cat.icon)
                }

                if !overflowIndices.isEmpty {
                    Menu {
                        ForEach(overflowIndices, id: \.self) { idx in
                            let cat = allCats[idx]
                            Button {
                                selectedCategory = cat.name
                            } label: {
                                Label(cat.name, systemImage: cat.icon)
                                    .foregroundStyle(theme.primaryTextColor)
                            }
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(theme.primaryTextColor)
                            .font(.caption)
                    }
                    .menuStyle(BorderlessButtonMenuStyle())
                    .tint(theme.badgeBackground)
                    .help("More categories")
                }
                Spacer(minLength: 0)
            }
            .tint(theme.badgeBackground)
            .frame(height: chipHeight)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(height: 38)
    }

    private func computeChipLayout(chipWidths: [CGFloat], availableWidth: CGFloat) -> (visible: [Int], overflow: [Int]) {
        var used: CGFloat = 0
        var visibleIndices: [Int] = []
        var overflowIndices: [Int] = []

        for (idx, w) in chipWidths.enumerated() {
            let reserveMore: CGFloat = 70
            if used + w + 4 <= availableWidth - reserveMore {
                visibleIndices.append(idx)
                used += w + 6
            } else {
                overflowIndices.append(idx)
            }
        }
        return (visibleIndices, overflowIndices)
    }

    private func chipView(name: String, icon: String) -> some View {
        let isSelected = (name == selectedCategory)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedCategory = name
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(name)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.clear : Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(name)
    }

    // MARK: - Enhanced Context Menu with Security
    
    @ViewBuilder
    private func rowContextMenu(for entry: PasswordEntry) -> some View {
        Button {
            selectedPassword = entry
        } label: {
            Label("Select", systemImage: "checkmark.circle")
        }
        
        Divider()
        
        Button {
            secureCopy(entry.serviceName ?? "", fieldName: "Service")
        } label: {
            Label("Copy Service", systemImage: "doc.on.doc")
        }
        
        Button {
            secureCopy(entry.username ?? "", fieldName: "Username")
        } label: {
            Label("Copy Username", systemImage: "person.crop.circle")
        }
        
        if let password = CoreDataHelper.decryptedPassword(for: entry) {
            Button {
                secureCopy(password, fieldName: "Password")
            } label: {
                Label("Copy Password", systemImage: "key")
            }
        }
        
        Divider()
        
        Button(role: .destructive) {
            showDeleteConfirm = entry
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
    
    // MARK: - Secure Copy with Auto-Clear
    
    private func secureCopy(_ text: String, fieldName: String) {
        // Cancel existing timer
        clipboardTimer?.invalidate()
        
        // Copy to clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        
        // Show feedback
        withAnimation {
            copiedField = fieldName
        }
        
        // Hide feedback after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copiedField = nil
            }
        }
        
        // Auto-clear clipboard if enabled
        if autoClearClipboard {
            clipboardTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(clearDelay), repeats: false) { _ in
                NSPasteboard.general.clearContents()
            }
        }
    }

    // MARK: - Enhanced Grid Tile
    
    private func passwordTile(_ entry: PasswordEntry) -> some View {
        let isSelected = selectedPassword == entry
        let isHovered = hoveredID == entry.objectID

        return VStack(spacing: 10) {
            // Service icon
            if let service = entry.serviceName, let first = service.first {
                let serviceColor = color(for: service)

                ZStack {
                    Circle()
                        .fill(serviceColor.opacity(0.15))
                        .frame(width: 48, height: 48)
                    
                    Circle()
                        .stroke(serviceColor.opacity(0.3), lineWidth: 2)
                        .frame(width: 48, height: 48)
                    
                    Text(String(first))
                        .font(.title2.bold())
                        .foregroundColor(serviceColor)
                }
            } else {
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "lock.fill")
                        .foregroundColor(.gray)
                }
            }

            // Service name
            Text(entry.serviceName ?? "Unknown Service")
                .font(.subheadline.bold())
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            // Category badge
            HStack(spacing: 4) {
                let catName = Self.displayName(for: entry.category)
                let iconName = CategoryIcons.icon(for: normalizedCategory(for: entry.category))
                
                Image(systemName: iconName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text(catName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.secondary.opacity(0.1)))
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.tileBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isSelected ? Color.accentColor : (isHovered ? Color.secondary.opacity(0.3) : Color.clear),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .shadow(color: .black.opacity(isSelected ? 0.15 : (isHovered ? 0.08 : 0.05)), radius: isSelected ? 8 : 4, y: 2)
        .scaleEffect(isSelected ? 1.02 : (isHovered ? 1.01 : 1.0))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onTapGesture {
            withAnimation {
                selectedPassword = entry
            }
        }
        .onHover { inside in hoveredID = inside ? entry.objectID : nil }
    }

    // MARK: - Enhanced List Row
    
    private func passwordRow(_ entry: PasswordEntry) -> some View {
        let isSelected = selectedPassword == entry
        let isHovered = hoveredID == entry.objectID
        let catName = Self.displayName(for: entry.category)
        let iconName = CategoryIcons.icon(for: normalizedCategory(for: entry.category))

        return HStack(spacing: 12) {
            // Service icon
            if let service = entry.serviceName, let first = service.first {
                let serviceColor = color(for: service)

                ZStack {
                    Circle()
                        .fill(serviceColor.opacity(0.15))
                        .frame(width: 40, height: 40)
                    
                    Circle()
                        .stroke(serviceColor.opacity(0.3), lineWidth: 2)
                        .frame(width: 40, height: 40)
                    
                    Text(String(first))
                        .font(.title3.bold())
                        .foregroundColor(serviceColor)
                }
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 40, height: 40)
            }

            // Service info
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.serviceName ?? "Unknown Service")
                    .font(.body.weight(.medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if let username = entry.username, !username.isEmpty {
                    Text(username)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Category badge
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text(catName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.secondary.opacity(0.1)))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.tileBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isSelected ? Color.accentColor : (isHovered ? Color.secondary.opacity(0.3) : Color.clear),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .shadow(color: .black.opacity(isSelected ? 0.12 : (isHovered ? 0.06 : 0.03)), radius: isSelected ? 6 : 3, y: 1)
        .scaleEffect(isSelected ? 1.01 : (isHovered ? 1.005 : 1.0))
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected || isHovered)
        .onHover { inside in
            withAnimation(.easeInOut(duration: 0.2)) {
                hoveredID = inside ? entry.objectID : nil
            }
        }
    }

    // MARK: - Color Helper
    
    private func color(for service: String) -> Color {
        if let brand = brandColors[service] {
            return brand
        }

        // 1️⃣ Deterministic hash from string
        var hash = 0
        for scalar in service.unicodeScalars {
            hash = Int(scalar.value) &+ (hash << 5) &- hash
        }

        // 2️⃣ Derive pseudo-random RGB components
        let red   = Double((hash & 0xFF0000) >> 16) / 255.0
        let green = Double((hash & 0x00FF00) >> 8) / 255.0
        let blue  = Double(hash & 0x0000FF) / 255.0

        // 3️⃣ Adjust base saturation and brightness (0.4–0.8 range)
        let adjustedRed = 0.4 + red * 0.4
        let adjustedGreen = 0.4 + green * 0.4
        let adjustedBlue = 0.4 + blue * 0.4

        // 4️⃣ Blend softly toward white for pastel look
        let blendFactor = 0.5 // higher → lighter pastel
        let pastelRed = adjustedRed * (1 - blendFactor) + blendFactor * 1.0
        let pastelGreen = adjustedGreen * (1 - blendFactor) + blendFactor * 1.0
        let pastelBlue = adjustedBlue * (1 - blendFactor) + blendFactor * 1.0

        return Color(red: pastelRed, green: pastelGreen, blue: pastelBlue)
    }
}

// MARK: - Category Helpers

private extension PasswordListView {
    static let noCategoryDisplayName = "No Category"

    static func displayName(for category: String?) -> String {
        guard let raw = category, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return noCategoryDisplayName
        }
        return raw
    }

    func normalizedCategory(for category: String?) -> String {
        let name = category?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (name?.isEmpty == false) ? name! : "Other"
    }
}
