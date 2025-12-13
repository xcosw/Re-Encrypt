import CoreData

// MARK: - CoreData Helper
@available(macOS 15.0, *)
@MainActor
struct CoreDataHelper {
    
    static func newSalt() -> Data {
        var d = Data(count: 32)
        let status = d.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }
        guard status == errSecSuccess else {
            fatalError("Failed to generate cryptographically secure random data")
        }
        return d
    }
    
    static func aadForEntry(id: UUID, createdAt: Date?) -> Data {
        var aad = Data()
        withUnsafeBytes(of: id.uuid) { buffer in
            aad.append(contentsOf: buffer)
        }
        if let t = createdAt {
            aad.append(contentsOf: "|".utf8)
            let timestamp = t.timeIntervalSince1970
            withUnsafeBytes(of: timestamp) { buffer in
                aad.append(contentsOf: buffer)
            }
        }
        return aad
    }
    
    // MARK: - Password CRUD
    
    static func savePassword(serviceName: String, username: String, lgdata: String?, countryCode: String?, phn: String, website: String, passwordData: Data, category: String, folder: Folder? = nil, notes: String? = nil, isFavorite: Bool = false, passwordExpiry: Date? = nil, tags: String? = nil, context: NSManagedObjectContext) async {
        guard await CryptoHelper.validateSecurityEnvironment() else { return }
        
        let salt = newSalt()
        let entryId = UUID()
        let createdAt = Date()
        let aad = aadForEntry(id: entryId, createdAt: createdAt)
        
        guard let encryptedPassword = await CryptoHelper.encryptPasswordData(passwordData, salt: salt, aad: aad) else { return }
        
        let entry = PasswordEntry(context: context)
        entry.id = entryId
        entry.serviceName = serviceName
        entry.username = username
        entry.lgdata = lgdata
        entry.countryCode = countryCode
        entry.phn = phn
        entry.website = website
        entry.encryptedPassword = encryptedPassword
        entry.salt = salt
        entry.category = category
        entry.createdAt = createdAt
        entry.updatedAt = createdAt
        entry.folder = folder
        entry.notes = notes
        entry.isFavorite = isFavorite
        entry.passwordExpiry = passwordExpiry
        entry.tags = tags
        
        do { try context.save() } catch { context.rollback() }
    }
    
    static func upsertPassword(entry: PasswordEntry? = nil, serviceName: String, username: String, lgdata: String? = nil, countryCode: String?, phn: String, website: String, passwordData: Data, category: String, folder: Folder? = nil, notes: String? = nil, isFavorite: Bool = false, passwordExpiry: Date? = nil, tags: String? = nil, context: NSManagedObjectContext) async {
        guard await CryptoHelper.validateSecurityEnvironment() else { return }
        
        let now = Date()
        let entryToUse: PasswordEntry
        let entryId: UUID
        let salt: Data
        
        if let existingEntry = entry {
            entryToUse = existingEntry
            entryId = existingEntry.id ?? UUID()
            salt = existingEntry.salt ?? newSalt()
            if existingEntry.createdAt == nil { existingEntry.createdAt = existingEntry.updatedAt ?? now }
            entryToUse.updatedAt = now
        } else {
            entryToUse = PasswordEntry(context: context)
            entryId = UUID()
            salt = newSalt()
            entryToUse.id = entryId
            entryToUse.salt = salt
            entryToUse.createdAt = now
            entryToUse.updatedAt = now
        }
        
        if entryToUse.createdAt == nil { entryToUse.createdAt = entryToUse.updatedAt ?? now }
        let aad = aadForEntry(id: entryId, createdAt: entryToUse.createdAt!)
        
        guard let encryptedPassword = await CryptoHelper.encryptPasswordData(passwordData, salt: salt, aad: aad) else { return }
        
        entryToUse.serviceName = serviceName
        entryToUse.username = username
        entryToUse.countryCode = countryCode
        entryToUse.phn = phn
        entryToUse.website = website
        entryToUse.lgdata = lgdata
        entryToUse.category = category
        entryToUse.encryptedPassword = encryptedPassword
        entryToUse.notes = notes
        entryToUse.isFavorite = isFavorite
        entryToUse.passwordExpiry = passwordExpiry
        entryToUse.tags = tags
        
        if let explicitFolder = folder {
            entryToUse.folder = explicitFolder
        } else if entry == nil {
            entryToUse.folder = await findMatchingFolder(for: category, context: context)
        }
        
        do { try context.save() } catch { context.rollback() }
    }
    
    static func updatePasswordData(for entry: PasswordEntry, newPasswordData: Data, context: NSManagedObjectContext) async -> Bool {
        guard await CryptoHelper.validateSecurityEnvironment() else { return false }
        guard let entryId = entry.id, let createdAt = entry.createdAt else { return false }
        
        let newSalt = newSalt()
        let aad = aadForEntry(id: entryId, createdAt: createdAt)
        guard let encryptedPassword = await CryptoHelper.encryptPasswordData(newPasswordData, salt: newSalt, aad: aad) else { return false }
        
        entry.encryptedPassword = encryptedPassword
        entry.salt = newSalt
        entry.updatedAt = Date()
        
        do { try context.save(); return true } catch { context.rollback(); return false }
    }
    
    static func decryptedPasswordData(for entry: PasswordEntry) async -> Data? {
        guard await CryptoHelper.validateSecurityEnvironment() else { return nil }
        guard let encrypted = entry.encryptedPassword, let salt = entry.salt, let id = entry.id else { return nil }
        let aad = aadForEntry(id: id, createdAt: entry.createdAt)
        return await CryptoHelper.decryptPasswordData(encrypted, salt: salt, aad: aad)
    }
    
    static func decryptedPassword(for entry: PasswordEntry) async -> SecData? {
        guard let data = await decryptedPasswordData(for: entry) else { return nil }
        return SecData(data)
    }
    
    static func decryptedPasswordString(for entry: PasswordEntry) async -> String? {
        guard let data = await decryptedPasswordData(for: entry) else { return nil }
        defer { var mutableData = data; mutableData.withUnsafeMutableBytes { ptr in guard let base = ptr.baseAddress else { return }; memset_s(base, ptr.count, 0, ptr.count) } }
        return String(data: data, encoding: .utf8)
    }
    
    static func deletePassword(_ entry: PasswordEntry, context: NSManagedObjectContext) {
        context.delete(entry)
        do { try context.save() } catch { context.rollback() }
    }
    
    static func fetchPasswords(context: NSManagedObjectContext) -> [PasswordEntry] {
        let request: NSFetchRequest<PasswordEntry> = PasswordEntry.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \PasswordEntry.createdAt, ascending: false)]
        return (try? context.fetch(request)) ?? []
    }
    
    static func fetchFavoritePasswords(context: NSManagedObjectContext) -> [PasswordEntry] {
        let request: NSFetchRequest<PasswordEntry> = PasswordEntry.fetchRequest()
        request.predicate = NSPredicate(format: "isFavorite == YES")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \PasswordEntry.updatedAt, ascending: false)]
        return (try? context.fetch(request)) ?? []
    }
    
    static func fetchExpiringPasswords(within days: Int, context: NSManagedObjectContext) -> [PasswordEntry] {
        let now = Date()
        let futureDate = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
        let request: NSFetchRequest<PasswordEntry> = PasswordEntry.fetchRequest()
        request.predicate = NSPredicate(format: "passwordExpiry != nil AND passwordExpiry <= %@ AND passwordExpiry >= %@", futureDate as NSDate, now as NSDate)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \PasswordEntry.passwordExpiry, ascending: true)]
        return (try? context.fetch(request)) ?? []
    }
    
    static func fetchPasswordsByTag(_ tag: String, context: NSManagedObjectContext) -> [PasswordEntry] {
        let request: NSFetchRequest<PasswordEntry> = PasswordEntry.fetchRequest()
        request.predicate = NSPredicate(format: "tags CONTAINS[cd] %@", tag)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \PasswordEntry.updatedAt, ascending: false)]
        return (try? context.fetch(request)) ?? []
    }
    
    static func fetchAllTags(context: NSManagedObjectContext) -> [String] {
        let request: NSFetchRequest<PasswordEntry> = PasswordEntry.fetchRequest()
        request.predicate = NSPredicate(format: "tags != nil AND tags != ''")
        guard let results = try? context.fetch(request) else { return [] }
        var allTags = Set<String>()
        for entry in results {
            if let tagsString = entry.tags, !tagsString.isEmpty {
                let tags = tagsString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                allTags.formUnion(tags)
            }
        }
        return Array(allTags).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

// MARK: - Folder CRUD
@available(macOS 15.0, *)
extension CoreDataHelper {
    static func createFolder(name: String, context: NSManagedObjectContext) async -> Folder? {
        guard await CryptoHelper.validateSecurityEnvironment() else { return nil }
        let folder = Folder(context: context)
        folder.id = UUID()
        let now = Date()
        folder.createdAt = now
        folder.updatedAt = now
        folder.orderIndex = Date().timeIntervalSince1970
        let salt = newSalt()
        folder.salt = salt
        guard let id = folder.id else { context.delete(folder); return nil }
        let aad = aadForEntry(id: id, createdAt: folder.createdAt)
        guard let encrypted = await CryptoHelper.encryptPasswordData(Data(name.utf8), salt: salt, aad: aad) else { context.delete(folder); return nil }
        folder.encryptedName = encrypted
        do { try context.save(); return folder } catch { context.rollback(); return nil }
    }
    
    static func renameFolder(_ folder: Folder, newName: String, context: NSManagedObjectContext) async {
        guard await CryptoHelper.validateSecurityEnvironment() else { return }
        guard let id = folder.id, let created = folder.createdAt, let salt = folder.salt else { return }
        let aad = aadForEntry(id: id, createdAt: created)
        guard let encrypted = await CryptoHelper.encryptPasswordData(Data(newName.utf8), salt: salt, aad: aad) else { return }
        folder.encryptedName = encrypted
        folder.updatedAt = Date()
        do { try context.save() } catch { context.rollback() }
    }
    
    static func deleteFolder(_ folder: Folder, moveItemsToUnfiled: Bool, context: NSManagedObjectContext) {
        let passwordSet: Set<PasswordEntry> = {
            if let swiftSet = folder.value(forKey: "passwords") as? Set<PasswordEntry> { return swiftSet }
            else if let nsset = folder.value(forKey: "passwords") as? NSSet, let converted = nsset as? Set<PasswordEntry> { return converted }
            else { return [] }
        }()
        if moveItemsToUnfiled { for entry in passwordSet { entry.folder = nil } }
        else { for entry in passwordSet { context.delete(entry) } }
        context.delete(folder)
        do { try context.save() } catch { context.rollback() }
    }
    
    static func decryptedFolderName(_ folder: Folder) async -> SecData? {
        guard let encrypted = folder.encryptedName, let salt = folder.salt, let id = folder.id else { return nil }
        let aad = aadForEntry(id: id, createdAt: folder.createdAt)
        guard let data = await CryptoHelper.decryptPasswordData(encrypted, salt: salt, aad: aad) else { return nil }
        return SecData(data)
    }
    
    static func decryptedFolderNameString(_ folder: Folder) async  -> String? {
        guard let secData = await decryptedFolderName(folder) else { return nil }
        defer { secData.clear() }
        return secData.withUnsafeBytes { ptr in guard let baseAddress = ptr.baseAddress else { return nil }; let data = Data(bytes: baseAddress, count: ptr.count); return String(data: data, encoding: .utf8) }
    }
    
    static func fetchFolders(context: NSManagedObjectContext) -> [Folder] {
        let request: NSFetchRequest<Folder> = Folder.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "orderIndex", ascending: true), NSSortDescriptor(key: "createdAt", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }
    
    static func totalPasswordsCount(context: NSManagedObjectContext) -> Int {
        let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: "PasswordEntry")
        fetch.resultType = .countResultType
        return (try? context.count(for: fetch)) ?? 0
    }
    
    static func unfiledPasswordsCount(context: NSManagedObjectContext) -> Int {
        let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: "PasswordEntry")
        fetch.predicate = NSPredicate(format: "folder == nil")
        fetch.resultType = .countResultType
        return (try? context.count(for: fetch)) ?? 0
    }
    
    static func countForFolder(_ folder: Folder, context: NSManagedObjectContext) -> Int {
        let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: "PasswordEntry")
        fetch.predicate = NSPredicate(format: "folder == %@", folder)
        fetch.resultType = .countResultType
        return (try? context.count(for: fetch)) ?? 0
    }
    
    static func findMatchingFolder(for category: String, context: NSManagedObjectContext) async -> Folder? {
        guard !category.isEmpty else { return nil }
        let fetchRequest: NSFetchRequest<Folder> = Folder.fetchRequest()
        do {
            let allFolders = try context.fetch(fetchRequest)
            let normalizedCategory = category.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            for folder in allFolders {
                if let secData = await decryptedFolderName(folder) {
                    defer { secData.clear() }
                    let folderName = secData.withUnsafeBytes { ptr in guard let base = ptr.baseAddress else { return "" }; let data = Data(bytes: base, count: ptr.count); return String(data: data, encoding: .utf8) ?? "" }
                    let normalizedFolderName = folderName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    if normalizedFolderName == normalizedCategory { return folder }
                }
            }
            return nil
        } catch { return nil }
    }
    
    static func countMatchingEntries(for folderName: String, context: NSManagedObjectContext) -> Int {
        let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: "PasswordEntry")
        fetch.predicate = NSPredicate(format: "category ==[c] %@ AND folder == nil", folderName)
        fetch.resultType = .countResultType
        return (try? context.count(for: fetch)) ?? 0
    }
    
    static func autoAssignEntriesToFolder(_ folder: Folder, context: NSManagedObjectContext) async {
        guard let secData = await decryptedFolderName(folder) else { return }
        defer { secData.clear() }
        let rawFolderName = secData.withUnsafeBytes { ptr in guard let base = ptr.baseAddress else { return "" }; let data = Data(bytes: base, count: ptr.count); return String(data: data, encoding: .utf8) ?? "" }
        guard !rawFolderName.isEmpty else { return }
        let fetchRequest: NSFetchRequest<PasswordEntry> = PasswordEntry.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "folder == nil AND category ==[c] %@", rawFolderName)
        do {
            let unfiledMatchingEntries = try context.fetch(fetchRequest)
            for entry in unfiledMatchingEntries { entry.folder = folder; entry.updatedAt = Date() }
            if !unfiledMatchingEntries.isEmpty { try context.save() }
        } catch { context.rollback() }
    }
}

// MARK: - PasswordEntry Extension
@available(macOS 15.0, *)
@MainActor
extension PasswordEntry {
    var hasTwoFactor: Bool { return encryptedTOTPSecret != nil && totpSalt != nil }
    
    func getDecryptedTOTPSecret() async -> SecData? {
        guard await CryptoHelper.validateSecurityEnvironment() else { return nil }
        guard let encryptedSecret = encryptedTOTPSecret, let salt = totpSalt, let id = self.id else { return nil }
        let aad = CoreDataHelper.aadForEntry(id: id, createdAt: createdAt)
        guard let decrypted = await CryptoHelper.decryptPasswordData(encryptedSecret, salt: salt, aad: aad) else { return nil }
        return SecData(decrypted)
    }
    
    func getDecryptedTOTPSecretString() async -> String? {
        guard let secData = await getDecryptedTOTPSecret() else { return nil }
        defer { secData.clear() }
        return secData.withUnsafeBytes { ptr in guard let baseAddress = ptr.baseAddress else { return nil }; let data = Data(bytes: baseAddress, count: ptr.count); return String(data: data, encoding: .utf8) }
    }
    
    func setEncryptedTOTPSecret(_ secret: String, context: NSManagedObjectContext) async -> Bool {
        guard let id = self.id else { return false }
        let salt = self.totpSalt ?? CoreDataHelper.newSalt()
        let aad = CoreDataHelper.aadForEntry(id: id, createdAt: createdAt)
        let secretData = Data(secret.utf8)
        guard let encrypted = await CryptoHelper.encryptPasswordData(secretData, salt: salt, aad: aad) else { return false }
        self.encryptedTOTPSecret = encrypted
        self.totpSalt = salt
        self.updatedAt = Date()
        do { try context.save(); return true } catch { context.rollback(); return false }
    }
    
    func removeTOTPSecret(context: NSManagedObjectContext) -> Bool {
        self.encryptedTOTPSecret = nil
        self.totpSalt = nil
        self.updatedAt = Date()
        do { try context.save(); return true } catch { return false }
    }
    
    func generateTOTPCode() async -> String? {
        guard let secret = await getDecryptedTOTPSecretString() else { return nil }
        return TOTPGenerator.generateCode(secret: secret)
    }
    
    var safeTagArray: [String] {
        guard let tagsString = tags, !tagsString.isEmpty else { return [] }
        return tagsString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    
    func hasSafeTag(_ tag: String) -> Bool { return safeTagArray.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) }
    
    var isSafelyExpiringSoon: Bool {
        guard let expiry = passwordExpiry else { return false }
        guard let daysUntil = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day else { return false }
        return daysUntil >= 0 && daysUntil <= 7
    }
    
    var isSafelyExpired: Bool {
        guard let expiry = passwordExpiry else { return false }
        return expiry < Date()
    }
    
    var safeDaysUntilExpiry: Int? {
        guard let expiry = passwordExpiry else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expiry).day
    }
}

// MARK: - Additional Helpers
@available(macOS 15.0, *)
extension CoreDataHelper {
    static func fetchFavoritePasswordsSafe(context: NSManagedObjectContext) -> [PasswordEntry] { return fetchFavoritePasswords(context: context) }
    static func fetchExpiringPasswordsSafe(within days: Int, context: NSManagedObjectContext) -> [PasswordEntry] { return fetchExpiringPasswords(within: days, context: context) }
    static func fetchPasswordsByTagSafe(_ tag: String, context: NSManagedObjectContext) -> [PasswordEntry] { return fetchPasswordsByTag(tag, context: context) }
    static func fetchAllTagsSafe(context: NSManagedObjectContext) -> [String] { return fetchAllTags(context: context) }
    
    static func updateNote(for entry: PasswordEntry, note: String?, context: NSManagedObjectContext) -> Bool {
        entry.notes = note
        entry.updatedAt = Date()
        do { try context.save(); return true } catch { context.rollback(); return false }
    }
    
    static func updateExpiry(for entry: PasswordEntry, expiry: Date?, context: NSManagedObjectContext) -> Bool {
        entry.passwordExpiry = expiry
        entry.updatedAt = Date()
        do { try context.save(); return true } catch { context.rollback(); return false }
    }
    
    static func updateTags(for entry: PasswordEntry, tags: [String], context: NSManagedObjectContext) -> Bool {
        let tagsString = tags.isEmpty ? nil : tags.joined(separator: ",")
        entry.tags = tagsString
        entry.updatedAt = Date()
        do { try context.save(); return true } catch { context.rollback(); return false }
    }
    
    static func fetch2FAPasswordsSafe(context: NSManagedObjectContext) -> [PasswordEntry] {
        let request: NSFetchRequest<PasswordEntry> = PasswordEntry.fetchRequest()
        request.predicate = NSPredicate(format: "encryptedTOTPSecret != nil AND totpSalt != nil")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \PasswordEntry.updatedAt, ascending: false)]
        return (try? context.fetch(request)) ?? []
    }
    
    static func count2FAPasswords(context: NSManagedObjectContext) -> Int {
        let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: "PasswordEntry")
        fetch.predicate = NSPredicate(format: "encryptedTOTPSecret != nil AND totpSalt != nil")
        fetch.resultType = .countResultType
        return (try? context.count(for: fetch)) ?? 0
    }
    
    @discardableResult
    static func toggleFavorite(for entry: PasswordEntry, context: NSManagedObjectContext) -> Bool {
        entry.isFavorite.toggle()
        entry.updatedAt = Date()
        do { try context.save(); return true } catch { context.rollback(); return false }
    }
    
    static func markAsFavorites(_ entries: [PasswordEntry], context: NSManagedObjectContext) -> Bool {
        for entry in entries { entry.isFavorite = true; entry.updatedAt = Date() }
        do { try context.save(); return true } catch { context.rollback(); return false }
    }
    
    static func removeFromFavorites(_ entries: [PasswordEntry], context: NSManagedObjectContext) -> Bool {
        for entry in entries { entry.isFavorite = false; entry.updatedAt = Date() }
        do { try context.save(); return true } catch { context.rollback(); return false }
    }
    
    static func searchPasswords(query: String, includeOnly2FA: Bool = false, context: NSManagedObjectContext) -> [PasswordEntry] {
        let request: NSFetchRequest<PasswordEntry> = PasswordEntry.fetchRequest()
        var predicates: [NSPredicate] = []
        if includeOnly2FA { predicates.append(NSPredicate(format: "encryptedTOTPSecret != nil AND totpSalt != nil")) }
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let searchPredicate = NSPredicate(format: "serviceName CONTAINS[cd] %@ OR username CONTAINS[cd] %@ OR website CONTAINS[cd] %@", query, query, query)
            predicates.append(searchPredicate)
        }
        if !predicates.isEmpty { request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates) }
        request.sortDescriptors = [NSSortDescriptor(keyPath: \PasswordEntry.updatedAt, ascending: false)]
        return (try? context.fetch(request)) ?? []
    }
    
    struct PasswordStatistics {
        let total: Int
        let favorites: Int
        let with2FA: Int
        let unfiled: Int
        let expiringSoon: Int
        let expired: Int
    }
    
    static func getStatistics(context: NSManagedObjectContext) -> PasswordStatistics {
        let total = totalPasswordsCount(context: context)
        let favorites = fetchFavoritePasswordsSafe(context: context).count
        let with2FA = count2FAPasswords(context: context)
        let unfiled = unfiledPasswordsCount(context: context)
        let expiringSoon = fetchExpiringPasswordsSafe(within: 7, context: context).count
        let expiredRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "PasswordEntry")
        expiredRequest.predicate = NSPredicate(format: "passwordExpiry != nil AND passwordExpiry < %@", Date() as NSDate)
        expiredRequest.resultType = .countResultType
        let expired = (try? context.count(for: expiredRequest)) ?? 0
        return PasswordStatistics(total: total, favorites: favorites, with2FA: with2FA, unfiled: unfiled, expiringSoon: expiringSoon, expired: expired)
    }
    
    static func findEntryByWebsite(_ url: String, context: NSManagedObjectContext) -> PasswordEntry? {
        let request: NSFetchRequest<PasswordEntry> = PasswordEntry.fetchRequest()
        request.predicate = NSPredicate(format: "website ==[c] %@", url)
        request.fetchLimit = 1
        return (try? context.fetch(request).first)
    }
}


