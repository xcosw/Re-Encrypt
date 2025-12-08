import SwiftUI
import CoreData

@available(macOS 15.0, *)
struct PasswordListView: View {
    @Environment(\.managedObjectContext) private var viewContext
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
    @State private var sortOption: SortOption = .dateNewest
    @State private var showSortMenu = false
    
    // ✅ Only keep clearDelay for SecureClipboard
    @AppStorage("clearDelay") private var clearDelay: Int = 10
    
    // ✅ NEW: Visual feedback for copy operations
    @State private var justCopied: String? = nil

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
                // Log unexpected state
#if DEBUG
                print("⚠️ Specific folder mode with no folder ID")
#endif
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
            if let folder = try viewContext.fetch(request).first {
                guard let secData = CoreDataHelper.decryptedFolderName(folder) else {
                    return false
                }
                defer { secData.clear() }
                
                let folderName = secData.withUnsafeBytes { ptr in
                    guard let base = ptr.baseAddress else { return "" }
                    let data = Data(bytes: base, count: ptr.count)
                    return String(data: data, encoding: .utf8) ?? ""
                }.lowercased()
                
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
        ZStack {
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
        .onChange(of: dynamicCategories.map(\.name)) { _ in
            if !dynamicCategories.map(\.name).contains(selectedCategory) {
                selectedCategory = "All"
            }
        }
        .id(fetchKey)
        .animation(.easeInOut, value: useGrid)
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
                let attributes: [NSAttributedString.Key: Any] = [.font: font]
                let textWidth = text.size(withAttributes: attributes).width
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

    // MARK: - ✅ ENHANCED CONTEXT MENU WITH SECURECLIPBOARD
    
    @ViewBuilder
    private func rowContextMenu(for entry: PasswordEntry) -> some View {
        Button {
            selectedPassword = entry
        } label: {
            Label("Select", systemImage: "checkmark.circle")
        }
        
        Divider()
        
        Button {
            copyWithFeedback(entry.serviceName ?? "", fieldName: "Service", entryID: entry.id ?? UUID())
        } label: {
            Label("Copy Service", systemImage: "doc.on.doc")
        }
        
        Button {
            copyWithFeedback(entry.username ?? "", fieldName: "Username", entryID: entry.id ?? UUID())
        } label: {
            Label("Copy Username", systemImage: "person.crop.circle")
        }
        
        if let secData = CoreDataHelper.decryptedPassword(for: entry) {
            Button {
                // Convert to String only when copying
                let password = secData.withUnsafeBytes { ptr in
                    guard let base = ptr.baseAddress else { return "" }
                    let data = Data(bytes: base, count: ptr.count)
                    return String(data: data, encoding: .utf8) ?? ""
                }
                
                copyWithFeedback(password, fieldName: "Password", entryID: entry.id ?? UUID())
                
                // SecData will be cleared when button scope ends
            } label: {
                Label("Copy Password", systemImage: "key")
            }
            .onDisappear {
                secData.clear()  // Cleanup when view disappears
            }
        }
        
        Divider()
        
        Button(role: .destructive) {
            showDeleteConfirm = entry
        } label: {
            Label("Delete", systemImage: "trash")
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

@available(macOS 15.0, *)
private extension PasswordListView {
    static let noCategoryDisplayName = "No Category"

    static func displayName(for category: String?) -> String {
        guard let raw = category, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return noCategoryDisplayName
        }
        
        // ✅ Use the mapping
        let lowercased = raw.lowercased()
        return categoryMapping[lowercased] ?? raw
    }

    func normalizedCategory(for category: String?) -> String {
        let name = category?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (name?.isEmpty == false) ? name! : "Other"
    }
}
