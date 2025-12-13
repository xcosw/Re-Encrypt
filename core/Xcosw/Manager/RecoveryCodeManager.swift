//
//  RecoveryCodeManager.swift
//  re-Encrypt
//
//  Created by xcosw.dev on 13.12.2025.
//

import Foundation

// MARK: - ========================================
// MARK: - 2. RECOVERY CODE MANAGER (Actor)
// MARK: - ========================================

@available(macOS 15.0, *)
actor RecoveryCodeManager {
    static let shared = RecoveryCodeManager()
    
    private let recoveryCodesKey = "RecoveryCodes.v3"
    private let recoveryCodesCount = 10
    
    private init() {}
    
    func generateRecoveryCodes(masterPassword: Data) async throws -> [String] {
        var codes: [String] = []
        
        for _ in 0..<recoveryCodesCount {
            // Generate 8-character alphanumeric codes
            let code = generateSecureCode(length: 8)
            codes.append(code)
        }
        
        // Encrypt and store codes
        guard let salt = await CryptoHelper.generateSalt() else {
            throw SecurityError.cryptographicFailure
        }
        
        let codesData = codes.joined(separator: ",").data(using: .utf8)!
        guard let encrypted = await CryptoHelper.encryptPasswordData(codesData, salt: salt) else {
            throw SecurityError.cryptographicFailure
        }
        
        // Store encrypted codes with salt
        let storage = RecoveryStorage(encrypted: encrypted, salt: salt, used: [])
        let storageData = try JSONEncoder().encode(storage)
        _ = await CryptoHelper.saveToLocalFileSecurely(storageData, name: recoveryCodesKey)
        
        await AuditLogger.shared.log("Recovery codes generated", level: .security)
        
        return codes
    }
    
    func verifyRecoveryCode(_ code: String, masterPassword: Data) async -> Bool {
        guard let storageData = await CryptoHelper.loadFromLocalFile(name: recoveryCodesKey),
              var storage = try? JSONDecoder().decode(RecoveryStorage.self, from: storageData) else {
            return false
        }
        
        guard let decrypted = await CryptoHelper.decryptPasswordData(storage.encrypted, salt: storage.salt),
              let codesString = String(data: decrypted, encoding: .utf8) else {
            return false
        }
        
        let codes = codesString.split(separator: ",").map(String.init)
        let normalizedCode = code.uppercased().replacingOccurrences(of: "-", with: "")
        
        // Check if code exists and hasn't been used
        guard codes.contains(normalizedCode), !storage.used.contains(normalizedCode) else {
            await AuditLogger.shared.log("Invalid or used recovery code attempted", level: .warning)
            return false
        }
        
        // Mark as used
        storage.used.append(normalizedCode)
        if let updatedData = try? JSONEncoder().encode(storage) {
            _ = await CryptoHelper.saveToLocalFileSecurely(updatedData, name: recoveryCodesKey)
        }
        
        await AuditLogger.shared.log("Recovery code used successfully", level: .security)
        return true
    }
    
    func hasRecoveryCodes() async -> Bool {
        return await CryptoHelper.loadFromLocalFile(name: recoveryCodesKey) != nil
    }
    
    func getRemainingCodesCount() async -> Int {
        guard let storageData = await CryptoHelper.loadFromLocalFile(name: recoveryCodesKey),
              let storage = try? JSONDecoder().decode(RecoveryStorage.self, from: storageData) else {
            return 0
        }
        return recoveryCodesCount - storage.used.count
    }
    
    private func generateSecureCode(length: Int) -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // Removed confusing chars
        var code = ""
        var randomData = Data(count: length)
        _ = randomData.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, length, buffer.baseAddress!)
        }
        
        for byte in randomData {
            let index = Int(byte) % chars.count
            code.append(chars[chars.index(chars.startIndex, offsetBy: index)])
        }
        
        // Format as XXXX-XXXX
        if length == 8 {
            return "\(code.prefix(4))-\(code.suffix(4))"
        }
        return code
    }
    
    struct RecoveryStorage: Codable {
        let encrypted: Data
        let salt: Data
        var used: [String]
    }
}
