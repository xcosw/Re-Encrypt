import SwiftUI

// MARK: - Sidebar

enum SidebarSelection: Hashable {
    case all
    case unfiled
    case favorites
    case twoFactor
    case folder(NSManagedObjectID)
}

// MARK: - Default Folder Suggestions

@available(macOS 15.0, *)
private struct DefaultFolders {
    static let suggestions = [
        "Banking",
        "Email",
        "Social",
        "Wi-Fi",
        "Work",
        "Shopping",
        "Streaming",
        "Gaming",
        "Government",
        "Health",
        "Education",
        "Travel",
        "Cryptocurrency"
    ]
    
    @MainActor static func createDefaultFolders(context: NSManagedObjectContext) async {
        for name in suggestions {
            // Check if folder already exists
            let existingFolder = await CoreDataHelper.findMatchingFolder(for: name, context: context)
            if existingFolder == nil {
                _ = await CoreDataHelper.createFolder(name: name, context: context)
            }
        }
    }
}

// MARK: - Enhanced Sidebar View

@available(macOS 15.0, *)
struct SidebarView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject var memoryMonitor: MemoryPressureMonitor
    
    @StateObject private var screenshotDetector = ScreenshotDetectionManager.shared
    
    @State private var showingNewFolderAlert = false
    @State private var showingDefaultFoldersAlert = false
    @State private var newFolderName: String = ""
    @State private var showSettings = false
    @State private var renamingFolderID: NSManagedObjectID?
    @State private var renameText: String = ""
    @FocusState private var renamingFieldFocused: Bool
    
    @Binding var selectedSidebar: SidebarSelection
    @Binding var foldersUseGrid: Bool
    
    
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(key: "orderIndex", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true)
        ],
        animation: .default
    )
    private var folders: FetchedResults<Folder>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            folderSection
            Spacer(minLength: 0)
            Divider()
            lockButton
            settings
        }
        .frame(minWidth: 220, maxWidth: 260)
        .frame(maxHeight: .infinity, alignment: .top)
        .appBackground()
    }
    
    // MARK: - Enhanced Header with Default Folders Button
    
    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(theme.badgeBackground.gradient)
                        .font(.title3)
                    
                    Text("Folders")
                        .font(.headline)
                        .foregroundColor(theme.primaryTextColor)
                }
                
                Spacer()
                
                HStack(spacing: 0) {
                    Button {
                        foldersUseGrid = false
                    } label: {
                        Image(systemName: "list.bullet")
                            .frame(width: 40, height: 24)
                            .background(foldersUseGrid ? .clear : theme.badgeBackground)
                            .foregroundStyle(foldersUseGrid ? theme.primaryTextColor : .white)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    Button {
                        foldersUseGrid = true
                    } label: {
                        Image(systemName: "square.grid.2x2")
                            .frame(width: 40, height: 24)
                            .background(foldersUseGrid ? theme.badgeBackground : .clear)
                            .foregroundStyle(foldersUseGrid ? .white : theme.primaryTextColor)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(theme.badgeBackground.opacity(0.4), lineWidth: 1)
                )
                .frame(width: 80)

                Menu {
                    Button {
                        createNewFolder()
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                    
                    Divider()
                    
                    Button {
                        showingDefaultFoldersAlert = true
                    } label: {
                        Label("Add Default Folders", systemImage: "folder.badge.gearshape")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(theme.badgeBackground.gradient)
                }
                .buttonStyle(.plain)
                .help("Create Folder")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .alert("New Folder", isPresented: $showingNewFolderAlert) {
            TextField("Folder Name", text: $newFolderName)
            Button("Create") {
                
                guard !newFolderName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                Task {
                    
                    if let newFolder = await CoreDataHelper.createFolder(name: newFolderName, context: viewContext) {
                        await CoreDataHelper.autoAssignEntriesToFolder(newFolder, context: viewContext)
                }}
                newFolderName = ""
            }
            Button("Cancel", role: .cancel) {
                newFolderName = ""
            }
        } message: {
            Text("Enter a name for your new folder")
        }
        .alert("Add Default Folders", isPresented: $showingDefaultFoldersAlert) {
            Button("Add All") {
                Task {
                    await
                DefaultFolders.createDefaultFolders(context: viewContext)
            }}
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will create default folders for common categories like Banking, Email, Social Media, Wi-Fi, etc.")
        }
    }

    // MARK: - Enhanced Folder Section with Special Categories
    
    private var folderSection: some View {
        Group {
            if foldersUseGrid {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        // Special categories
                        folderGridTile(title: "All", icon: "tray.full.fill", count: totalPasswordsCount(), selection: .all)
                        folderGridTile(title: "Favorites", icon: "star.fill", count: favoritesCount(), selection: .favorites)
                        folderGridTile(title: "2FA Codes", icon: "lock.shield.fill", count: twoFactorCount(), selection: .twoFactor)
                        folderGridTile(title: "Unfiled", icon: "tray", count: unfiledPasswordsCount(), selection: .unfiled)
                        
                        // User folders
                        ForEach(folders, id: \.objectID) { folder in
                            FolderGridTileView(
                                folder: folder,
                                selectedSidebar: $selectedSidebar,
                                renamingFolderID: $renamingFolderID,
                                renameText: $renameText,
                                renamingFieldFocused: $renamingFieldFocused
                            )
                            .environmentObject(theme)
                        }

                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
                }
            } else {
                List(selection: $selectedSidebar) {
                    Section {
                        folderListTile(title: "All", icon: "tray.full.fill", count: totalPasswordsCount(), selection: .all)
                        folderListTile(title: "Favorites", icon: "star.fill", count: favoritesCount(), selection: .favorites)
                        folderListTile(title: "2FA Codes", icon: "lock.shield.fill", count: twoFactorCount(), selection: .twoFactor)
                        folderListTile(title: "Unfiled", icon: "tray", count: unfiledPasswordsCount(), selection: .unfiled)
                    } header: {
                        Text("Quick Access")
                            .font(.caption.bold())
                            .foregroundColor(theme.secondaryTextColor)
                    }
                    
                    if !folders.isEmpty {
                        Section {
                            ForEach(folders, id: \.objectID) { folder in
                                FolderListTileView(
                                    folder: folder,
                                    selectedSidebar: $selectedSidebar,
                                    renamingFolderID: $renamingFolderID,
                                    renameText: $renameText,
                                    renamingFieldFocused: $renamingFieldFocused
                                )
                                .environmentObject(theme)
                            }

                        } header: {
                            Text("My Folders")
                                .font(.caption.bold())
                                .foregroundColor(theme.secondaryTextColor)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }
    
    // MARK: - Grid Tile (Enhanced)
    
    @ViewBuilder
    private func folderGridTile(title: String, icon: String, count: Int, selection: SidebarSelection) -> some View {
        let isSelected = selectedSidebar == selection
        
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedSidebar = selection
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isSelected ? theme.badgeBackground : theme.badgeBackground.opacity(0.12))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : theme.badgeBackground)
                }
                
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isSelected ? theme.badgeBackground : theme.primaryTextColor)
                    .lineLimit(1)
                
                countBadge(count, isSelected: isSelected)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? theme.adaptiveSelectionFill : theme.adaptiveTileBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? theme.badgeBackground : Color.clear, lineWidth: 2)
            )
            .shadow(color: isSelected ? theme.badgeBackground.opacity(0.2) : .clear, radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
    
    
    // MARK: - List Tile (Enhanced)
    
    @ViewBuilder
    private func folderListTile(title: String, icon: String, count: Int, selection: SidebarSelection) -> some View {
        NavigationLink(value: selection) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(theme.badgeBackground.gradient)
                    .frame(width: 24)
                
                Text(title)
                    .font(.body)
                    .foregroundColor(theme.primaryTextColor)
                
                Spacer()
                
                countBadge(count, isSelected: false)
            }
            .contentShape(Rectangle())
        }
    }
    
   
    
    // MARK: - Count Badge
    
    private func countBadge(_ count: Int, isSelected: Bool) -> some View {
        Text("\(count)")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(isSelected ? theme.badgeBackground.opacity(0.9) : theme.badgeBackground)
                    .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
            )
    }
    
    // MARK: - Lock Button
    
    private var lockButton: some View {
        Button {
            NotificationCenter.default.post(name: .applicationLocked, object: nil)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.body.weight(.semibold))
                
                Text("Lock App")
                    .font(.body.weight(.semibold))
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [.red, .red.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(10)
            .shadow(color: .red.opacity(0.3), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .help("Lock the app immediately")
    }
     
    private var settings: some View {
        Button {
            showSettings = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "gearshape.fill")
                    .font(.body.weight(.semibold))
                
                Text("Settings")
                    .font(.body.weight(.semibold))
                
                Spacer()
                
                Image(systemName: "gearshape")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [theme.badgeBackground, theme.badgeBackground.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(10)
            .shadow(color: theme.badgeBackground.opacity(0.3), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .help("Open Settings menu")
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(\.managedObjectContext, viewContext)
                .environmentObject(theme)
                .environmentObject(memoryMonitor)
                .environmentObject(screenshotDetector)
        }
    }
    
    // MARK: - Helper Functions
    
    private func createNewFolder() {
        newFolderName = ""
        showingNewFolderAlert = true
    }
    
    private func startRenaming(_ folder: Folder, name: String) {
        renameText = name
        renamingFolderID = folder.objectID
        renamingFieldFocused = true
    }
    
    private func renameFolder(_ folder: Folder) {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cancelRenaming()
            return
        }
        Task{
            await CoreDataHelper.renameFolder(folder, newName: trimmed, context: viewContext)
            await CoreDataHelper.autoAssignEntriesToFolder(folder, context: viewContext)
        }
        cancelRenaming()
    }
   
    private func cancelRenaming() {
        renamingFolderID = nil
        renameText = ""
        renamingFieldFocused = false
    }
    
    private func deleteFolder(_ folder: Folder) {
        CoreDataHelper.deleteFolder(folder, moveItemsToUnfiled: true, context: viewContext)
        if selectedSidebar == .folder(folder.objectID) {
            selectedSidebar = .all
        }
    }
    
    // MARK: - Count Functions
    
    private func totalPasswordsCount() -> Int {
        CoreDataHelper.totalPasswordsCount(context: viewContext)
    }
    
    private func unfiledPasswordsCount() -> Int {
        CoreDataHelper.unfiledPasswordsCount(context: viewContext)
    }
    
    private func favoritesCount() -> Int {
        CoreDataHelper.fetchFavoritePasswordsSafe(context: viewContext).count
    }
    
    private func twoFactorCount() -> Int {
        CoreDataHelper.fetch2FAPasswordsSafe(context: viewContext).count
    }
    
    private func countForFolder(_ folder: Folder) -> Int {
        CoreDataHelper.countForFolder(folder, context: viewContext)
    }
}


@available(macOS 15.0, *)
struct FolderGridTileView: View {
    let folder: Folder

    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.managedObjectContext) private var context

    @Binding var selectedSidebar: SidebarSelection
    @Binding var renamingFolderID: NSManagedObjectID?
    @Binding var renameText: String
    @FocusState.Binding var renamingFieldFocused: Bool

    @State private var folderName: String = "Folder"

    var body: some View {
        let folderID = folder.objectID
        let isSelected = selectedSidebar == .folder(folderID)
        let isRenaming = renamingFolderID == folderID

        let normalizedName = folderName.replacingOccurrences(of: "-", with: "")
        let iconName =
            CategoryIcons.allKnown.contains(normalizedName)
            ? CategoryIcons.icon(for: normalizedName)
            : "folder.fill"

        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedSidebar = .folder(folderID)
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isSelected ? theme.badgeBackground : theme.badgeBackground.opacity(0.12))
                        .frame(width: 44, height: 44)

                    Image(systemName: iconName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : theme.badgeBackground)
                }

                if isRenaming {
                    TextField("Name", text: $renameText, onCommit: {
                        renameFolder()
                    })
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .focused($renamingFieldFocused)
                    .onAppear { renamingFieldFocused = true }
                } else {
                    Text(folderName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isSelected ? theme.badgeBackground : theme.primaryTextColor)
                        .lineLimit(1)
                }

                countBadge(countForFolder(folder), isSelected: isSelected)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? theme.adaptiveSelectionFill : theme.adaptiveTileBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? theme.badgeBackground : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .task {
            // ✅ async happens HERE
            if let name = await CoreDataHelper.decryptedFolderNameString(folder) {
                folderName = name
            }
        }
        .onTapGesture(count: 2) {
            renameText = folderName
            renamingFolderID = folderID
        }
        .contextMenu {
            Button {
                renameText = folderName
                renamingFolderID = folderID
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                CoreDataHelper.deleteFolder(folder, moveItemsToUnfiled: true, context: context)
            } label: {
                Label("Delete Folder", systemImage: "trash")
            }
        }
    }

    private func renameFolder() {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        Task {
            await CoreDataHelper.renameFolder(folder, newName: trimmed, context: context)
            await CoreDataHelper.autoAssignEntriesToFolder(folder, context: context)
        }

        renamingFolderID = nil
        renameText = ""
        renamingFieldFocused = false
    }

    private func countForFolder(_ folder: Folder) -> Int {
        CoreDataHelper.countForFolder(folder, context: context)
    }

    private func countBadge(_ count: Int, isSelected: Bool) -> some View {
        Text("\(count)")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(isSelected ? theme.badgeBackground.opacity(0.9) : theme.badgeBackground)
            )
    }
}

@available(macOS 15.0, *)
struct FolderListTileView: View {
    let folder: Folder

    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.managedObjectContext) private var context

    @Binding var selectedSidebar: SidebarSelection
    @Binding var renamingFolderID: NSManagedObjectID?
    @Binding var renameText: String
    @FocusState.Binding var renamingFieldFocused: Bool

    @State private var folderName: String = "Folder"

    var body: some View {
        let folderID = folder.objectID
        let isRenaming = renamingFolderID == folderID

        let normalizedName = folderName.replacingOccurrences(of: "-", with: "")
        let iconName =
            CategoryIcons.allKnown.contains(normalizedName)
            ? CategoryIcons.icon(for: normalizedName)
            : "folder.fill"

        NavigationLink(value: SidebarSelection.folder(folderID)) {
            HStack(spacing: 10) {
                if isRenaming {
                    TextField("Folder Name", text: $renameText, onCommit: renameFolder)
                        .textFieldStyle(.roundedBorder)
                        .focused($renamingFieldFocused)
                        .onAppear { renamingFieldFocused = true }
                } else {
                    Image(systemName: iconName)
                        .font(.body)
                        .foregroundStyle(theme.badgeBackground.gradient)
                        .frame(width: 24)

                    Text(folderName)
                        .font(.body)
                        .foregroundColor(theme.primaryTextColor)

                    Spacer()

                    countBadge(countForFolder(folder))
                }
            }
            .contentShape(Rectangle())
        }
        .onTapGesture {
            selectedSidebar = .folder(folderID)
        }
        .onTapGesture(count: 2) {
            renameText = folderName
            renamingFolderID = folderID
        }
        .contextMenu {
            Button {
                renameText = folderName
                renamingFolderID = folderID
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                CoreDataHelper.deleteFolder(folder, moveItemsToUnfiled: true, context: context)
            } label: {
                Label("Delete Folder", systemImage: "trash")
            }
        }
        .task {
            // ✅ async belongs HERE
            if let name = await CoreDataHelper.decryptedFolderNameString(folder) {
                folderName = name
            }
        }
    }

    private func renameFolder() {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        Task {
            await CoreDataHelper.renameFolder(folder, newName: trimmed, context: context)
            await CoreDataHelper.autoAssignEntriesToFolder(folder, context: context)
        }

        renamingFolderID = nil
        renameText = ""
        renamingFieldFocused = false
    }

    private func countForFolder(_ folder: Folder) -> Int {
        CoreDataHelper.countForFolder(folder, context: context)
    }

    private func countBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(theme.badgeBackground)
            )
    }
}
