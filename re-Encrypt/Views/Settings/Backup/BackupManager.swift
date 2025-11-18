// MARK: - Backup Models

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
@MainActor
struct BackupManager {
    
    // MARK: - Export
    
    /// Export backup with optional additional encryption
    static func exportBackup(
        context: NSManagedObjectContext,
        masterPassword: String,
        exportPassword: String?,
        decryptBeforeExport: Bool = false
    ) throws -> Data {
        
        // Verify master password first
        guard CryptoHelper.verifyMasterPassword(
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
                  let website = entry.website,
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
    ) throws -> (entries: Int, folders: Int) {
        
        // Verify master password first
        guard CryptoHelper.verifyMasterPassword(
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
