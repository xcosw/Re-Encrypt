// MARK: - Backup Models
/*
import Foundation
import CryptoKit
import CoreData
import SwiftUI
import AppKit
import CommonCrypto

// MARK: - Backup Models

struct BackupMetadata: Codable {
    var version: String = "1.0"
    let createdAt: Date
    let deviceIdentifier: String
    let entryCount: Int
    let folderCount: Int
    let isEncrypted: Bool
}

struct BackupPasswordEntry: Codable {
    let id: UUID
    let serviceName: String
    let username: String
    let lgdata: String?
    let website: String?
    let encryptedPassword: Data
    let salt: Data
    let category: String
    let createdAt: Date?
    let updatedAt: Date?
    let folderID: UUID?
}

struct BackupFolder: Codable {
    let id: UUID
    let encryptedName: Data
    let salt: Data
    let createdAt: Date?
    let updatedAt: Date?
    let orderIndex: Double
}

struct BackupData: Codable {
    let metadata: BackupMetadata
    let entries: [BackupPasswordEntry]
    let folders: [BackupFolder]
}

// MARK: - Backup Manager

enum BackupError: Error, LocalizedError {
    case notUnlocked
    case exportFailed(String)
    case importFailed(String)
    case encryptionFailed
    case decryptionFailed
    case invalidBackupFormat
    case passwordRequired
    case masterPasswordIncorrect
    
    var errorDescription: String? {
        switch self {
        case .notUnlocked: return "App must be unlocked to perform backup operations"
        case .exportFailed(let msg): return "Export failed: \(msg)"
        case .importFailed(let msg): return "Import failed: \(msg)"
        case .encryptionFailed: return "Failed to encrypt backup"
        case .decryptionFailed: return "Failed to decrypt backup - check password"
        case .invalidBackupFormat: return "Invalid backup file format"
        case .passwordRequired: return "Backup password required"
        case .masterPasswordIncorrect: return "Master password is incorrect"
        }
    }
}

@available(macOS 15.0, *)
@MainActor
struct BackupManager {
    
    // MARK: - Export
    
    /// Export backup with optional additional encryption
    static func exportBackup(
        context: NSManagedObjectContext,
        masterPassword: String,
        exportPassword: String?,
        decryptBeforeExport: Bool = false
    ) async throws -> Data {
        
        // Verify master password first
        guard await CryptoHelper.verifyMasterPassword(
            password: Data(masterPassword.utf8),
            context: context
        ) else {
            throw BackupError.masterPasswordIncorrect
        }
        
        guard CryptoHelper.isUnlocked else {
            throw BackupError.notUnlocked
        }
        
        // Fetch all entries
        let entriesRequest: NSFetchRequest<PasswordEntry> = PasswordEntry.fetchRequest()
        entriesRequest.sortDescriptors = [NSSortDescriptor(keyPath: \PasswordEntry.createdAt, ascending: true)]
        let entries = try context.fetch(entriesRequest)
        
        // Fetch all folders
        let foldersRequest: NSFetchRequest<Folder> = Folder.fetchRequest()
        foldersRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Folder.createdAt, ascending: true)]
        let folders = try context.fetch(foldersRequest)
        
        // Create backup entries
        var backupEntries: [BackupPasswordEntry] = []
        
        for entry in entries {
            guard let id = entry.id,
                  let serviceName = entry.serviceName,
                  //let website = entry.website,
                  let username = entry.username,
                  let encryptedPwd = entry.encryptedPassword,
                  let salt = entry.salt,
                  let category = entry.category else {
                continue
            }
            
            var finalEncryptedPwd = encryptedPwd
            var finalSalt = salt
            
            // If decrypting before export (plaintext or re-encrypt)
            if decryptBeforeExport || exportPassword != nil {
                // Decrypt with current master key
                guard let plainPassword = CoreDataHelper.decryptedPassword(for: entry) else {
                    throw BackupError.exportFailed("Failed to decrypt entry: \(serviceName)")
                }
                
                if let exportPwd = exportPassword {
                    // Re-encrypt with export password
                    let exportSalt = newRandomSalt()
                    let aad = backupAAD(for: id)
                    
                    guard let reencrypted = encryptForBackup(
                        plaintext: plainPassword,
                        password: exportPwd,
                        salt: exportSalt,
                        aad: aad
                    ) else {
                        throw BackupError.encryptionFailed
                    }
                    
                    finalEncryptedPwd = reencrypted
                    finalSalt = exportSalt
                } else {
                    // Export as plaintext (store password as UTF-8 data)
                    finalEncryptedPwd = Data(plainPassword.utf8)
                    finalSalt = Data() // Empty salt indicates plaintext
                }
            }
            
            backupEntries.append(BackupPasswordEntry(
                id: id,
                serviceName: serviceName,
                username: username,
                lgdata: entry.lgdata,
                website: entry.website,
                encryptedPassword: finalEncryptedPwd,
                salt: finalSalt,
                category: category,
                createdAt: entry.createdAt,
                updatedAt: entry.updatedAt,
                folderID: entry.folder?.id
            ))
        }
        
        // Create backup folders
        var backupFolders: [BackupFolder] = []
        
        for folder in folders {
            guard let id = folder.id,
                  let encryptedName = folder.encryptedName,
                  let salt = folder.salt else {
                continue
            }
            
            var finalEncryptedName = encryptedName
            var finalSalt = salt
            
            // If decrypting before export (plaintext or re-encrypt)
            if decryptBeforeExport || exportPassword != nil {
                // Decrypt with current master key
                guard let plainName = CoreDataHelper.decryptedFolderName(folder) else {
                    throw BackupError.exportFailed("Failed to decrypt folder name")
                }
                
                if let exportPwd = exportPassword {
                    // Re-encrypt with export password
                    let exportSalt = newRandomSalt()
                    let aad = backupAAD(for: id)
                    
                    guard let reencrypted = encryptForBackup(
                        plaintext: plainName,
                        password: exportPwd,
                        salt: exportSalt,
                        aad: aad
                    ) else {
                        throw BackupError.encryptionFailed
                    }
                    
                    finalEncryptedName = reencrypted
                    finalSalt = exportSalt
                } else {
                    // Export as plaintext
                    finalEncryptedName = Data(plainName.utf8)
                    finalSalt = Data()
                }
            }
            
            backupFolders.append(BackupFolder(
                id: id,
                encryptedName: finalEncryptedName,
                salt: finalSalt,
                createdAt: folder.createdAt,
                updatedAt: folder.updatedAt,
                orderIndex: folder.orderIndex
            ))
        }
        
        // Create metadata
        let metadata = BackupMetadata(
            createdAt: Date(),
            deviceIdentifier: getBackupDeviceID(),
            entryCount: backupEntries.count,
            folderCount: backupFolders.count,
            isEncrypted: exportPassword != nil || !decryptBeforeExport
        )
        
        let backup = BackupData(
            metadata: metadata,
            entries: backupEntries,
            folders: backupFolders
        )
        
        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let jsonData = try encoder.encode(backup)
        
        // If export password provided, encrypt the entire JSON
        if let exportPwd = exportPassword, !exportPwd.isEmpty {
            let outerSalt = newRandomSalt()
            guard let encrypted = encryptBackupFile(
                jsonData: jsonData,
                password: exportPwd,
                salt: outerSalt
            ) else {
                throw BackupError.encryptionFailed
            }
            return encrypted
        }
        
        return jsonData
    }
    
    // MARK: - Import
    
    /// Import backup with automatic format detection
    static func importBackup(
        backupData: Data,
        masterPassword: String,
        importPassword: String?,
        context: NSManagedObjectContext,
        replaceExisting: Bool = false
    ) async throws -> (entries: Int, folders: Int) {
        
        // Verify master password first
        guard await CryptoHelper.verifyMasterPassword(
            password: Data(masterPassword.utf8),
            context: context
        ) else {
            throw BackupError.masterPasswordIncorrect
        }
        
        guard CryptoHelper.isUnlocked else {
            throw BackupError.notUnlocked
        }
        
        var jsonData = backupData
        var wasEncrypted = false
        
        // Try to decrypt if it's an encrypted file
        // Check if this looks like encrypted data (not JSON)
        if let firstChar = String(data: backupData.prefix(1), encoding: .utf8),
           firstChar != "{" && firstChar != "[" {
            // Doesn't start with JSON, probably encrypted
            if let pwd = importPassword, !pwd.isEmpty {
                do {
                    jsonData = try decryptBackupFile(encryptedData: backupData, password: pwd)
                    wasEncrypted = true
                    NSLog("✅ Backup file decrypted successfully")
                } catch {
                    NSLog("❌ Failed to decrypt backup file: \(error)")
                    throw BackupError.decryptionFailed
                }
            } else {
                NSLog("❌ Backup appears encrypted but no password provided")
                throw BackupError.passwordRequired
            }
        }
        
        // Decode JSON
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let backup: BackupData
        do {
            backup = try decoder.decode(BackupData.self, from: jsonData)
            NSLog("✅ Backup JSON decoded: \(backup.entries.count) entries, \(backup.folders.count) folders")
        } catch {
            NSLog("❌ JSON decode error: \(error)")
            // Log first 100 chars to debug
            if let preview = String(data: jsonData.prefix(100), encoding: .utf8) {
                NSLog("JSON preview: \(preview)")
            }
            throw BackupError.invalidBackupFormat
        }
        
        // Validate backup
        guard backup.metadata.version == "1.0" else {
            throw BackupError.importFailed("Unsupported backup version: \(backup.metadata.version)")
        }
        
        NSLog("📦 Backup metadata: encrypted=\(backup.metadata.isEncrypted), entries=\(backup.metadata.entryCount), folders=\(backup.metadata.folderCount)")
        
        // Clear existing data if requested
        if replaceExisting {
            try clearAllData(context: context)
        }
        
        // Import folders first (to establish relationships)
        var folderMap: [UUID: Folder] = [:]
        
        for backupFolder in backup.folders {
            let folder = Folder(context: context)
            folder.id = backupFolder.id
            folder.createdAt = backupFolder.createdAt
            folder.updatedAt = backupFolder.updatedAt
            folder.orderIndex = backupFolder.orderIndex
            
            // Determine how folder is encrypted
            let needsDecryption = !backupFolder.salt.isEmpty
            
            if !needsDecryption {
                // Plaintext folder - re-encrypt with current master key
                let plainName = String(data: backupFolder.encryptedName, encoding: .utf8) ?? "Unknown"
                NSLog("📁 Importing plaintext folder: \(plainName)")
                
                let newSalt = newRandomSalt()
                // Use CoreDataHelper's AAD format (UUID + createdAt)
                let aad = coreDataAAD(for: backupFolder.id, createdAt: folder.createdAt)
                
                guard let encrypted = CryptoHelper.encryptPassword(plainName, salt: newSalt, aad: aad) else {
                    throw BackupError.importFailed("Failed to encrypt folder: \(plainName)")
                }
                
                folder.salt = newSalt
                folder.encryptedName = encrypted
                
            } else if backup.metadata.isEncrypted && importPassword != nil && !importPassword!.isEmpty && wasEncrypted {
                // Encrypted with backup password - decrypt then re-encrypt with master key
                do {
                    let plainName = try decryptFromBackup(
                        encrypted: backupFolder.encryptedName,
                        password: importPassword!,
                        salt: backupFolder.salt,
                        aad: backupAAD(for: backupFolder.id)
                    )
                    NSLog("📁 Importing encrypted folder: \(plainName)")
                    
                    let newSalt = newRandomSalt()
                    // Use CoreDataHelper's AAD format (UUID + createdAt)
                    let aad = coreDataAAD(for: backupFolder.id, createdAt: folder.createdAt)
                    
                    guard let reencrypted = CryptoHelper.encryptPassword(plainName, salt: newSalt, aad: aad) else {
                        throw BackupError.importFailed("Failed to re-encrypt folder")
                    }
                    
                    folder.salt = newSalt
                    folder.encryptedName = reencrypted
                } catch {
                    NSLog("❌ Failed to decrypt folder with backup password: \(error)")
                    throw BackupError.importFailed("Failed to decrypt folder - check backup password")
                }
                
            } else {
                // Already encrypted with master key (direct export) - keep as-is
                NSLog("📁 Importing master-key encrypted folder (keeping encryption)")
                folder.salt = backupFolder.salt
                folder.encryptedName = backupFolder.encryptedName
            }
            
            folderMap[backupFolder.id] = folder
        }
        
        // Import entries
        var successCount = 0
        for backupEntry in backup.entries {
            let entry = PasswordEntry(context: context)
            entry.id = backupEntry.id
            entry.serviceName = backupEntry.serviceName
            entry.username = backupEntry.username
            entry.lgdata = backupEntry.lgdata
            entry.website = backupEntry.website
            entry.category = backupEntry.category
            entry.createdAt = backupEntry.createdAt
            entry.updatedAt = backupEntry.updatedAt
            
            // Link to folder if exists
            if let folderID = backupEntry.folderID {
                entry.folder = folderMap[folderID]
            }
            
            // Determine how entry is encrypted
            let needsDecryption = !backupEntry.salt.isEmpty
            
            if !needsDecryption {
                // Plaintext entry - re-encrypt with current master key
                let plainPassword = String(data: backupEntry.encryptedPassword, encoding: .utf8) ?? ""
                
                let newSalt = newRandomSalt()
                // Use CoreDataHelper's AAD format (UUID + createdAt)
                let aad = coreDataAAD(for: backupEntry.id, createdAt: entry.createdAt)
                
                guard let encrypted = CryptoHelper.encryptPassword(plainPassword, salt: newSalt, aad: aad) else {
                    NSLog("❌ Failed to encrypt entry: \(backupEntry.serviceName)")
                    continue
                }
                
                entry.salt = newSalt
                entry.encryptedPassword = encrypted
                successCount += 1
                
            } else if backup.metadata.isEncrypted && importPassword != nil && !importPassword!.isEmpty && wasEncrypted {
                // Encrypted with backup password - decrypt then re-encrypt with master key
                do {
                    let plainPassword = try decryptFromBackup(
                        encrypted: backupEntry.encryptedPassword,
                        password: importPassword!,
                        salt: backupEntry.salt,
                        aad: backupAAD(for: backupEntry.id)
                    )
                    
                    let newSalt = newRandomSalt()
                    // Use CoreDataHelper's AAD format (UUID + createdAt)
                    let aad = coreDataAAD(for: backupEntry.id, createdAt: entry.createdAt)
                    
                    guard let reencrypted = CryptoHelper.encryptPassword(plainPassword, salt: newSalt, aad: aad) else {
                        NSLog("❌ Failed to re-encrypt entry: \(backupEntry.serviceName)")
                        continue
                    }
                    
                    entry.salt = newSalt
                    entry.encryptedPassword = reencrypted
                    successCount += 1
                } catch {
                    NSLog("❌ Failed to decrypt entry \(backupEntry.serviceName): \(error)")
                    throw BackupError.importFailed("Failed to decrypt entry: \(backupEntry.serviceName)")
                }
                
            } else {
                // Already encrypted with master key (direct export) - keep as-is
                entry.salt = backupEntry.salt
                entry.encryptedPassword = backupEntry.encryptedPassword
                successCount += 1
            }
        }
        
        // Save context
        try context.save()
        
        NSLog("✅ Imported \(successCount) entries and \(folderMap.count) folders")
        return (entries: successCount, folders: folderMap.count)
    }
    
    // MARK: - Helper Functions
    
    private static func newRandomSalt() -> Data {
        var salt = Data(count: 32)
        let status = salt.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, 32, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            fatalError("Failed to generate random salt")
        }
        return salt
    }
    
    private static func backupAAD(for id: UUID) -> Data {
        return Data("backup-v1-\(id.uuidString)".utf8)
    }
    
    // CoreDataHelper uses UUID + createdAt for AAD
    private static func coreDataAAD(for id: UUID, createdAt: Date?) -> Data {
        var s = id.uuidString
        if let t = createdAt {
            let fmt = ISO8601DateFormatter()
            s += "|" + fmt.string(from: t)
        }
        return Data(s.utf8)
    }
    
    private static func getBackupDeviceID() -> String {
        return ProcessInfo.processInfo.hostName
    }
    
    // MARK: - Backup-Specific Encryption
    
    private static func encryptForBackup(
        plaintext: String,
        password: String,
        salt: Data,
        aad: Data
    ) -> Data? {
        
        let passwordData = Data(password.utf8)
        let key = deriveBackupKey(password: passwordData, salt: salt)
        
        do {
            let sealed = try AES.GCM.seal(Data(plaintext.utf8), using: key, authenticating: aad)
            return sealed.combined
        } catch {
            NSLog("❌ Backup encryption failed: \(error)")
            return nil
        }
    }
    
    private static func decryptFromBackup(
        encrypted: Data,
        password: String,
        salt: Data,
        aad: Data
    ) throws -> String {
        
        let passwordData = Data(password.utf8)
        let key = deriveBackupKey(password: passwordData, salt: salt)
        
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: encrypted)
            let decrypted = try AES.GCM.open(sealedBox, using: key, authenticating: aad)
            
            guard let plaintext = String(data: decrypted, encoding: .utf8) else {
                throw BackupError.decryptionFailed
            }
            
            return plaintext
        } catch {
            NSLog("❌ Backup decryption failed: \(error)")
            throw BackupError.decryptionFailed
        }
    }
    
    private static func encryptBackupFile(
        jsonData: Data,
        password: String,
        salt: Data
    ) -> Data? {
        
        let passwordData = Data(password.utf8)
        let key = deriveBackupKey(password: passwordData, salt: salt)
        
        do {
            let aad = Data("backup-file-v1".utf8)
            let sealed = try AES.GCM.seal(jsonData, using: key, authenticating: aad)
            
            var result = Data()
            result.append(salt)
            result.append(sealed.combined!)
            
            return result
        } catch {
            NSLog("❌ Backup file encryption failed: \(error)")
            return nil
        }
    }
    
    private static func decryptBackupFile(
        encryptedData: Data,
        password: String
    ) throws -> Data {
        
        guard encryptedData.count > 32 else {
            throw BackupError.invalidBackupFormat
        }
        
        let salt = encryptedData.prefix(32)
        let sealedData = encryptedData.dropFirst(32)
        
        let passwordData = Data(password.utf8)
        let key = deriveBackupKey(password: passwordData, salt: salt)
        
        do {
            let aad = Data("backup-file-v1".utf8)
            let sealedBox = try AES.GCM.SealedBox(combined: sealedData)
            return try AES.GCM.open(sealedBox, using: key, authenticating: aad)
        } catch {
            NSLog("❌ Backup file decryption failed: \(error)")
            throw BackupError.decryptionFailed
        }
    }
    
    private static func deriveBackupKey(password: Data, salt: Data) -> SymmetricKey {
        var derived = [UInt8](repeating: 0, count: 32)
        
        let result = password.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes.bindMemory(to: Int8.self).baseAddress,
                    passwordBytes.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress,
                    saltBytes.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    600_000,
                    &derived,
                    derived.count
                )
            }
        }
        
        guard result == kCCSuccess else {
            fatalError("PBKDF2 derivation failed for backup")
        }
        
        return SymmetricKey(data: Data(derived))
    }
    
    private static func clearAllData(context: NSManagedObjectContext) throws {
        let entriesRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "PasswordEntry")
        let deleteEntries = NSBatchDeleteRequest(fetchRequest: entriesRequest)
        
        let foldersRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "Folder")
        let deleteFolders = NSBatchDeleteRequest(fetchRequest: foldersRequest)
        
        try context.execute(deleteEntries)
        try context.execute(deleteFolders)
        try context.save()
        
        NSLog("🗑️ Cleared all existing data")
    }
}
*/

// MARK: - Enhanced Backup Models with All Fields

import Foundation
import CryptoKit
import CoreData
import SwiftUI
import AppKit
import CommonCrypto

// MARK: - Backup Models

struct BackupMetadata: Codable {
    var version: String = "1.1" // Incremented for new fields
    let createdAt: Date
    let deviceIdentifier: String
    let entryCount: Int
    let folderCount: Int
    let isEncrypted: Bool
    let includes2FA: Bool // NEW: indicates if 2FA data is present
    let includesExtendedFields: Bool // NEW: indicates notes, tags, etc.
}

struct BackupPasswordEntry: Codable {
    let id: UUID
    let serviceName: String
    let username: String
    let lgdata: String?
    let countryCode: String? // ADDED
    let phn: String // ADDED
    let website: String?
    let encryptedPassword: Data
    let salt: Data
    let category: String
    let createdAt: Date?
    let updatedAt: Date?
    let folderID: UUID?
    
    // NEW EXTENDED FIELDS
    let notes: String? // ADDED
    let isFavorite: Bool // ADDED
    let passwordExpiry: Date? // ADDED
    let tags: String? // ADDED
    
    // NEW 2FA FIELDS
    let encryptedTOTPSecret: Data? // ADDED
    let totpSalt: Data? // ADDED
}

struct BackupFolder: Codable {
    let id: UUID
    let encryptedName: Data
    let salt: Data
    let createdAt: Date?
    let updatedAt: Date?
    let orderIndex: Double
}

struct BackupData: Codable {
    let metadata: BackupMetadata
    let entries: [BackupPasswordEntry]
    let folders: [BackupFolder]
}

// MARK: - Enhanced Backup Manager

enum BackupError: Error, LocalizedError {
    case notUnlocked
    case exportFailed(String)
    case importFailed(String)
    case encryptionFailed
    case decryptionFailed
    case invalidBackupFormat
    case passwordRequired
    case masterPasswordIncorrect
    
    var errorDescription: String? {
        switch self {
        case .notUnlocked: return "App must be unlocked to perform backup operations"
        case .exportFailed(let msg): return "Export failed: \(msg)"
        case .importFailed(let msg): return "Import failed: \(msg)"
        case .encryptionFailed: return "Failed to encrypt backup"
        case .decryptionFailed: return "Failed to decrypt backup - check password"
        case .invalidBackupFormat: return "Invalid backup file format"
        case .passwordRequired: return "Backup password required"
        case .masterPasswordIncorrect: return "Master password is incorrect"
        }
    }
}

@available(macOS 15.0, *)
@MainActor
struct BackupManager {
    
    // MARK: - Enhanced Export with All Fields
    
    /// Export backup with optional additional encryption - includes ALL fields
    static func exportBackup(
        context: NSManagedObjectContext,
        masterPassword: String,
        exportPassword: String?,
        decryptBeforeExport: Bool = false
    ) async throws -> Data {
        
        // Verify master password first
        guard await CryptoHelper.verifyMasterPassword(
            password: Data(masterPassword.utf8),
            context: context
        ) else {
            throw BackupError.masterPasswordIncorrect
        }
        
        guard CryptoHelper.isUnlocked else {
            throw BackupError.notUnlocked
        }
        
        // Fetch all entries
        let entriesRequest: NSFetchRequest<PasswordEntry> = PasswordEntry.fetchRequest()
        entriesRequest.sortDescriptors = [NSSortDescriptor(keyPath: \PasswordEntry.createdAt, ascending: true)]
        let entries = try context.fetch(entriesRequest)
        
        // Fetch all folders
        let foldersRequest: NSFetchRequest<Folder> = Folder.fetchRequest()
        foldersRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Folder.createdAt, ascending: true)]
        let folders = try context.fetch(foldersRequest)
        
        // Track if backup includes 2FA
        var includes2FA = false
        
        // Create backup entries with ALL fields
        var backupEntries: [BackupPasswordEntry] = []
        
        for entry in entries {
            guard let id = entry.id,
                  let serviceName = entry.serviceName,
                  let username = entry.username,
                  let encryptedPwd = entry.encryptedPassword,
                  let salt = entry.salt,
                  let category = entry.category else {
                continue
            }
            
            var finalEncryptedPwd = encryptedPwd
            var finalSalt = salt
            
            // Handle password encryption
            if decryptBeforeExport || exportPassword != nil {
                guard let secData = CoreDataHelper.decryptedPassword(for: entry) else {
                    throw BackupError.exportFailed("Failed to decrypt entry: \(serviceName)")
                }
                defer { secData.clear() }
                
                // Convert SecData to String for processing
                let plainPassword = secData.withUnsafeBytes { ptr in
                    guard let base = ptr.baseAddress else { return "" }
                    let data = Data(bytes: base, count: ptr.count)
                    return String(data: data, encoding: .utf8) ?? ""
                }
                
                if let exportPwd = exportPassword {
                    let exportSalt = newRandomSalt()
                    let aad = backupAAD(for: id)
                    
                    guard let reencrypted = encryptForBackup(
                        plaintext: plainPassword,  // ✅ Now a String
                        password: exportPwd,
                        salt: exportSalt,
                        aad: aad
                    ) else {
                        throw BackupError.encryptionFailed
                    }
                    
                    finalEncryptedPwd = reencrypted
                    finalSalt = exportSalt
                } else {
                    // Plaintext export
                    finalEncryptedPwd = Data(plainPassword.utf8)  // ✅ Works now
                    finalSalt = Data()
                }
            }

            
            // Handle 2FA encryption (NEW)
            var finalEncryptedTOTP: Data? = nil
            var finalTOTPSalt: Data? = nil
            
            if let encryptedTOTP = entry.encryptedTOTPSecret,
               let totpSalt = entry.totpSalt {
                includes2FA = true
                
                if decryptBeforeExport || exportPassword != nil {
                    // Decrypt TOTP secret
                    if let secData = entry.getDecryptedTOTPSecret() {
                        defer { secData.clear() }
                        
                        // Convert SecData to String
                        let plainTOTP = secData.withUnsafeBytes { ptr in
                            guard let base = ptr.baseAddress else { return "" }
                            let data = Data(bytes: base, count: ptr.count)
                            return String(data: data, encoding: .utf8) ?? ""
                        }
                        
                        if let exportPwd = exportPassword {
                            // Re-encrypt with export password
                            let exportTOTPSalt = newRandomSalt()
                            let aad = backupAAD(for: id, suffix: "-totp")
                            
                            if let reencrypted = encryptForBackup(
                                plaintext: plainTOTP,  // ✅ Now a String
                                password: exportPwd,
                                salt: exportTOTPSalt,
                                aad: aad
                            ) {
                                finalEncryptedTOTP = reencrypted
                                finalTOTPSalt = exportTOTPSalt
                            } else {
                                NSLog("⚠️ Failed to re-encrypt TOTP for: \(serviceName)")
                            }
                        } else {
                            // Plaintext export
                            finalEncryptedTOTP = Data(plainTOTP.utf8)  // ✅ Works now
                            finalTOTPSalt = Data()
                        }
                    } else {
                        NSLog("⚠️ Failed to decrypt TOTP for: \(serviceName)")
                    }
                } else {
                    // Keep master-key encrypted
                    finalEncryptedTOTP = encryptedTOTP
                    finalTOTPSalt = totpSalt
                }
            }
            
            backupEntries.append(BackupPasswordEntry(
                id: id,
                serviceName: serviceName,
                username: username,
                lgdata: entry.lgdata,
                countryCode: entry.countryCode, // NEW
                phn: entry.phn ?? "", // NEW
                website: entry.website,
                encryptedPassword: finalEncryptedPwd,
                salt: finalSalt,
                category: category,
                createdAt: entry.createdAt,
                updatedAt: entry.updatedAt,
                folderID: entry.folder?.id,
                notes: entry.notes, // NEW
                isFavorite: entry.isFavorite, // NEW
                passwordExpiry: entry.passwordExpiry, // NEW
                tags: entry.tags, // NEW
                encryptedTOTPSecret: finalEncryptedTOTP, // NEW
                totpSalt: finalTOTPSalt // NEW
            ))
        }
        
        // Create backup folders (unchanged)
        var backupFolders: [BackupFolder] = []
        
        for folder in folders {
            guard let id = folder.id,
                  let encryptedName = folder.encryptedName,
                  let salt = folder.salt else {
                continue
            }
            
            var finalEncryptedName = encryptedName
            var finalSalt = salt
            
            if decryptBeforeExport || exportPassword != nil {
                guard let plainName = CoreDataHelper.decryptedFolderNameString(folder) else {
                    throw BackupError.exportFailed("Failed to decrypt folder name")
                }
                
                if let exportPwd = exportPassword {
                    let exportSalt = newRandomSalt()
                    let aad = backupAAD(for: id)
                    
                    guard let reencrypted = encryptForBackup(
                        plaintext: plainName,
                        password: exportPwd,
                        salt: exportSalt,
                        aad: aad
                    ) else {
                        throw BackupError.encryptionFailed
                    }
                    
                    finalEncryptedName = reencrypted
                    finalSalt = exportSalt
                } else {
                    finalEncryptedName = Data(plainName.utf8)
                    finalSalt = Data()
                }
            }
            
            backupFolders.append(BackupFolder(
                id: id,
                encryptedName: finalEncryptedName,
                salt: finalSalt,
                createdAt: folder.createdAt,
                updatedAt: folder.updatedAt,
                orderIndex: folder.orderIndex
            ))
        }
        
        // Create enhanced metadata
        let metadata = BackupMetadata(
            version: "1.1",
            createdAt: Date(),
            deviceIdentifier: getBackupDeviceID(),
            entryCount: backupEntries.count,
            folderCount: backupFolders.count,
            isEncrypted: exportPassword != nil || !decryptBeforeExport,
            includes2FA: includes2FA, // NEW
            includesExtendedFields: true // NEW
        )
        
        let backup = BackupData(
            metadata: metadata,
            entries: backupEntries,
            folders: backupFolders
        )
        
        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let jsonData = try encoder.encode(backup)
        
        NSLog("✅ Created backup: \(backupEntries.count) entries, \(backupFolders.count) folders, 2FA: \(includes2FA)")
        
        // If export password provided, encrypt the entire JSON
        if let exportPwd = exportPassword, !exportPwd.isEmpty {
            let outerSalt = newRandomSalt()
            guard let encrypted = encryptBackupFile(
                jsonData: jsonData,
                password: exportPwd,
                salt: outerSalt
            ) else {
                throw BackupError.encryptionFailed
            }
            return encrypted
        }
        
        return jsonData
    }
    
    // MARK: - Enhanced Import with All Fields
    
    /// Import backup with automatic format detection - handles ALL fields
    static func importBackup(
        backupData: Data,
        masterPassword: String,
        importPassword: String?,
        context: NSManagedObjectContext,
        replaceExisting: Bool = false
    ) async throws -> (entries: Int, folders: Int, with2FA: Int) {
        
        // Verify master password first
        guard await CryptoHelper.verifyMasterPassword(
            password: Data(masterPassword.utf8),
            context: context
        ) else {
            throw BackupError.masterPasswordIncorrect
        }
        
        guard CryptoHelper.isUnlocked else {
            throw BackupError.notUnlocked
        }
        
        var jsonData = backupData
        var wasEncrypted = false
        
        // Try to decrypt if it's an encrypted file
        if let firstChar = String(data: backupData.prefix(1), encoding: .utf8),
           firstChar != "{" && firstChar != "[" {
            if let pwd = importPassword, !pwd.isEmpty {
                do {
                    jsonData = try decryptBackupFile(encryptedData: backupData, password: pwd)
                    wasEncrypted = true
                    NSLog("✅ Backup file decrypted successfully")
                } catch {
                    NSLog("❌ Failed to decrypt backup file: \(error)")
                    throw BackupError.decryptionFailed
                }
            } else {
                NSLog("❌ Backup appears encrypted but no password provided")
                throw BackupError.passwordRequired
            }
        }
        
        // Decode JSON
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let backup: BackupData
        do {
            backup = try decoder.decode(BackupData.self, from: jsonData)
            NSLog("✅ Backup decoded: v\(backup.metadata.version), \(backup.entries.count) entries, \(backup.folders.count) folders")
            NSLog("   2FA: \(backup.metadata.includes2FA), Extended: \(backup.metadata.includesExtendedFields)")
        } catch {
            NSLog("❌ JSON decode error: \(error)")
            if let preview = String(data: jsonData.prefix(200), encoding: .utf8) {
                NSLog("JSON preview: \(preview)")
            }
            throw BackupError.invalidBackupFormat
        }
        
        // Validate backup version
        if backup.metadata.version != "1.0" && backup.metadata.version != "1.1" {
            throw BackupError.importFailed("Unsupported backup version: \(backup.metadata.version)")
        }
        
        // Clear existing data if requested
        if replaceExisting {
            try clearAllData(context: context)
        }
        
        // Import folders first
        var folderMap: [UUID: Folder] = [:]
        
        for backupFolder in backup.folders {
            let folder = Folder(context: context)
            folder.id = backupFolder.id
            folder.createdAt = backupFolder.createdAt
            folder.updatedAt = backupFolder.updatedAt
            folder.orderIndex = backupFolder.orderIndex
            
            let needsDecryption = !backupFolder.salt.isEmpty
            
            if !needsDecryption {
                // Plaintext folder
                let plainName = String(data: backupFolder.encryptedName, encoding: .utf8) ?? "Unknown"
                let newSalt = newRandomSalt()
                let aad = coreDataAAD(for: backupFolder.id, createdAt: folder.createdAt)
                
                guard let encrypted = CryptoHelper.encryptPasswordFolde(plainName, salt: newSalt, aad: aad) else {
                    throw BackupError.importFailed("Failed to encrypt folder: \(plainName)")
                }
                
                folder.salt = newSalt
                folder.encryptedName = encrypted
                
            } else if backup.metadata.isEncrypted && importPassword != nil && !importPassword!.isEmpty && wasEncrypted {
                // Encrypted with backup password
                do {
                    let plainName = try decryptFromBackup(
                        encrypted: backupFolder.encryptedName,
                        password: importPassword!,
                        salt: backupFolder.salt,
                        aad: backupAAD(for: backupFolder.id)
                    )
                    
                    let newSalt = newRandomSalt()
                    let aad = coreDataAAD(for: backupFolder.id, createdAt: folder.createdAt)
                    
                    guard let reencrypted = CryptoHelper.encryptPasswordFolde(plainName, salt: newSalt, aad: aad) else {
                        throw BackupError.importFailed("Failed to re-encrypt folder")
                    }
                    
                    folder.salt = newSalt
                    folder.encryptedName = reencrypted
                } catch {
                    throw BackupError.importFailed("Failed to decrypt folder - check backup password")
                }
                
            } else {
                // Master-key encrypted
                folder.salt = backupFolder.salt
                folder.encryptedName = backupFolder.encryptedName
            }
            
            folderMap[backupFolder.id] = folder
        }
        
        // Import entries with ALL fields
        var successCount = 0
        var with2FACount = 0
        
        for backupEntry in backup.entries {
            let entry = PasswordEntry(context: context)
            entry.id = backupEntry.id
            entry.serviceName = backupEntry.serviceName
            entry.username = backupEntry.username
            entry.lgdata = backupEntry.lgdata
            entry.countryCode = backupEntry.countryCode // NEW
            entry.phn = backupEntry.phn // NEW
            entry.website = backupEntry.website
            entry.category = backupEntry.category
            entry.createdAt = backupEntry.createdAt
            entry.updatedAt = backupEntry.updatedAt
            
            // NEW EXTENDED FIELDS
            entry.notes = backupEntry.notes
            entry.isFavorite = backupEntry.isFavorite
            entry.passwordExpiry = backupEntry.passwordExpiry
            entry.tags = backupEntry.tags
            
            // Link to folder
            if let folderID = backupEntry.folderID {
                entry.folder = folderMap[folderID]
            }
            
            // Handle password
            let needsDecryption = !backupEntry.salt.isEmpty
            
            if !needsDecryption {
                // Plaintext password
                let plainPassword = String(data: backupEntry.encryptedPassword, encoding: .utf8) ?? ""
                let newSalt = newRandomSalt()
                let aad = coreDataAAD(for: backupEntry.id, createdAt: entry.createdAt)
                
                guard let encrypted = CryptoHelper.encryptPasswordFolde(plainPassword, salt: newSalt, aad: aad) else {
                    NSLog("❌ Failed to encrypt entry: \(backupEntry.serviceName)")
                    continue
                }
                
                entry.salt = newSalt
                entry.encryptedPassword = encrypted
                
            } else if backup.metadata.isEncrypted && importPassword != nil && !importPassword!.isEmpty && wasEncrypted {
                // Encrypted with backup password
                do {
                    let plainPassword = try decryptFromBackup(
                        encrypted: backupEntry.encryptedPassword,
                        password: importPassword!,
                        salt: backupEntry.salt,
                        aad: backupAAD(for: backupEntry.id)
                    )
                    
                    let newSalt = newRandomSalt()
                    let aad = coreDataAAD(for: backupEntry.id, createdAt: entry.createdAt)
                    
                    guard let reencrypted = CryptoHelper.encryptPasswordFolde(plainPassword, salt: newSalt, aad: aad) else {
                        NSLog("❌ Failed to re-encrypt entry: \(backupEntry.serviceName)")
                        continue
                    }
                    
                    entry.salt = newSalt
                    entry.encryptedPassword = reencrypted
                } catch {
                    throw BackupError.importFailed("Failed to decrypt entry: \(backupEntry.serviceName)")
                }
                
            } else {
                // Master-key encrypted
                entry.salt = backupEntry.salt
                entry.encryptedPassword = backupEntry.encryptedPassword
            }
            
            // Handle 2FA (NEW)
            if let encryptedTOTP = backupEntry.encryptedTOTPSecret,
               let totpSalt = backupEntry.totpSalt {
                
                let needsTOTPDecryption = !totpSalt.isEmpty
                
                if !needsTOTPDecryption {
                    // Plaintext TOTP
                    if let plainTOTP = String(data: encryptedTOTP, encoding: .utf8) {
                        let newTOTPSalt = newRandomSalt()
                        let aad = coreDataAAD(for: backupEntry.id, createdAt: entry.createdAt, suffix: "-totp")
                        let totpData = Data(plainTOTP.utf8)
                        
                        if let encrypted = CryptoHelper.encryptPasswordData(totpData, salt: newTOTPSalt, aad: aad) {
                            entry.encryptedTOTPSecret = encrypted
                            entry.totpSalt = newTOTPSalt
                            with2FACount += 1
                        }
                    }
                    
                } else if backup.metadata.isEncrypted && importPassword != nil && !importPassword!.isEmpty && wasEncrypted {
                    // Encrypted with backup password
                    do {
                        let plainTOTP = try decryptFromBackup(
                            encrypted: encryptedTOTP,
                            password: importPassword!,
                            salt: totpSalt,
                            aad: backupAAD(for: backupEntry.id, suffix: "-totp")
                        )
                        
                        let newTOTPSalt = newRandomSalt()
                        let aad = coreDataAAD(for: backupEntry.id, createdAt: entry.createdAt, suffix: "-totp")
                        let totpData = Data(plainTOTP.utf8)
                        
                        if let reencrypted = CryptoHelper.encryptPasswordData(totpData, salt: newTOTPSalt, aad: aad) {
                            entry.encryptedTOTPSecret = reencrypted
                            entry.totpSalt = newTOTPSalt
                            with2FACount += 1
                        }
                    } catch {
                        NSLog("⚠️ Failed to decrypt TOTP for: \(backupEntry.serviceName)")
                    }
                    
                } else {
                    // Master-key encrypted
                    entry.encryptedTOTPSecret = encryptedTOTP
                    entry.totpSalt = totpSalt
                    with2FACount += 1
                }
            }
            
            successCount += 1
        }
        
        // Save context
        try context.save()
        
        NSLog("✅ Imported \(successCount) entries (\(with2FACount) with 2FA) and \(folderMap.count) folders")
        return (entries: successCount, folders: folderMap.count, with2FA: with2FACount)
    }
    
    // MARK: - Helper Functions
    
    private static func newRandomSalt() -> Data {
        var salt = Data(count: 32)
        let status = salt.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, 32, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            fatalError("Failed to generate random salt")
        }
        return salt
    }
    
    private static func backupAAD(for id: UUID, suffix: String = "") -> Data {
        return Data("backup-v1-\(id.uuidString)\(suffix)".utf8)
    }
    
    private static func coreDataAAD(for id: UUID, createdAt: Date?, suffix: String = "") -> Data {
        var s = id.uuidString
        if let t = createdAt {
            s += "|" + String(format: "%.3f", t.timeIntervalSince1970)
        }
        s += suffix
        return Data(s.utf8)
    }
    
    private static func getBackupDeviceID() -> String {
        return ProcessInfo.processInfo.hostName
    }
    
    // MARK: - Backup-Specific Encryption
    
    private static func encryptForBackup(
        plaintext: String,
        password: String,
        salt: Data,
        aad: Data
    ) -> Data? {
        
        let passwordData = Data(password.utf8)
        let key = deriveBackupKey(password: passwordData, salt: salt)
        
        do {
            let sealed = try AES.GCM.seal(Data(plaintext.utf8), using: key, authenticating: aad)
            return sealed.combined
        } catch {
            NSLog("❌ Backup encryption failed: \(error)")
            return nil
        }
    }
    
    private static func decryptFromBackup(
        encrypted: Data,
        password: String,
        salt: Data,
        aad: Data
    ) throws -> String {
        
        let passwordData = Data(password.utf8)
        let key = deriveBackupKey(password: passwordData, salt: salt)
        
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: encrypted)
            let decrypted = try AES.GCM.open(sealedBox, using: key, authenticating: aad)
            
            guard let plaintext = String(data: decrypted, encoding: .utf8) else {
                throw BackupError.decryptionFailed
            }
            
            return plaintext
        } catch {
            NSLog("❌ Backup decryption failed: \(error)")
            throw BackupError.decryptionFailed
        }
    }
    
    private static func encryptBackupFile(
        jsonData: Data,
        password: String,
        salt: Data
    ) -> Data? {
        
        let passwordData = Data(password.utf8)
        let key = deriveBackupKey(password: passwordData, salt: salt)
        
        do {
            let aad = Data("backup-file-v1".utf8)
            let sealed = try AES.GCM.seal(jsonData, using: key, authenticating: aad)
            
            var result = Data()
            result.append(salt)
            result.append(sealed.combined!)
            
            return result
        } catch {
            NSLog("❌ Backup file encryption failed: \(error)")
            return nil
        }
    }
    
    private static func decryptBackupFile(
        encryptedData: Data,
        password: String
    ) throws -> Data {
        
        guard encryptedData.count > 32 else {
            throw BackupError.invalidBackupFormat
        }
        
        let salt = encryptedData.prefix(32)
        let sealedData = encryptedData.dropFirst(32)
        
        let passwordData = Data(password.utf8)
        let key = deriveBackupKey(password: passwordData, salt: salt)
        
        do {
            let aad = Data("backup-file-v1".utf8)
            let sealedBox = try AES.GCM.SealedBox(combined: sealedData)
            return try AES.GCM.open(sealedBox, using: key, authenticating: aad)
        } catch {
            NSLog("❌ Backup file decryption failed: \(error)")
            throw BackupError.decryptionFailed
        }
    }
    
    private static func deriveBackupKey(password: Data, salt: Data) -> SymmetricKey {
        var derived = [UInt8](repeating: 0, count: 32)
        
        let result = password.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes.bindMemory(to: Int8.self).baseAddress,
                    passwordBytes.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress,
                    saltBytes.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    600_000,
                    &derived,
                    derived.count
                )
            }
        }
        
        guard result == kCCSuccess else {
            fatalError("PBKDF2 derivation failed for backup")
        }
        
        return SymmetricKey(data: Data(derived))
    }
    
    private static func clearAllData(context: NSManagedObjectContext) throws {
        let entriesRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "PasswordEntry")
        let deleteEntries = NSBatchDeleteRequest(fetchRequest: entriesRequest)
        
        let foldersRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "Folder")
        let deleteFolders = NSBatchDeleteRequest(fetchRequest: foldersRequest)
        
        try context.execute(deleteEntries)
        try context.execute(deleteFolders)
        try context.save()
        
        NSLog("🗑️ Cleared all existing data")
    }
}
