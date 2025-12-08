import Foundation
import CryptoKit
import CoreData

// MARK: - 2FA Manager with Encrypted Storage
@available(macOS 15.0, *)
@MainActor
class TwoFactorAuthManager {
    @MainActor static let shared = TwoFactorAuthManager()
    
    // Use encrypted keychain storage like other sensitive data
    private let secretKey = "TwoFactorAuth.Secret.Encrypted.v1"
    private let backupCodesKey = "TwoFactorAuth.BackupCodes.Encrypted.v1"
    private let enabledKey = "TwoFactorAuth.Enabled.Encrypted.v1"
    
    private init() {}
    
    // MARK: - 2FA State (now encrypted)
    
    var isEnabled: Bool {
        get {
            // Check if encrypted secret exists
            return loadEncryptedFromKeychain(key: enabledKey) != nil
        }
    }
    
    // MARK: - Setup 2FA
    
    /// Generate a new TOTP secret and return it with QR code data
    func setup() -> (secret: String, qrCodeURL: String, backupCodes: [String])? {
        // Generate 160-bit (20 byte) secret
        var secretData = Data(count: 20)
        let result = secretData.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, 20, buffer.baseAddress!)
        }
        
        guard result == errSecSuccess else {
            return nil
        }
        
        // Encode as Base32
        let secret = base32Encode(secretData)
        
        // Generate backup codes
        let backupCodes = generateBackupCodes(count: 10)
        
        // Create QR code URL for authenticator apps
        let appName = "PasswordManager"
        let issuer = "SecureVault"
        let qrCodeURL = "otpauth://totp/\(issuer):\(appName)?secret=\(secret)&issuer=\(issuer)"
        
        return (secret, qrCodeURL, backupCodes)
    }
    
    /// Enable 2FA with the provided secret
    func enable(secret: String, backupCodes: [String], masterPassword: Data) -> Bool {
        guard CryptoHelper.keyStorage != nil else {
            return false
        }
        
        // Encrypt secret using master password
        let secretData = Data(secret.utf8)
        let salt = generateSalt()
        guard let encryptedSecret = CryptoHelper.encryptPasswordData(secretData, salt: salt, aad: aadFor2FA()) else {
            return false
        }
        
        // Combine salt + encrypted data
        var combinedSecret = salt
        combinedSecret.append(encryptedSecret)
        
        // Encrypt backup codes
        let codesData = Data(backupCodes.joined(separator: ",").utf8)
        let codesSalt = generateSalt()
        guard let encryptedCodes = CryptoHelper.encryptPasswordData(codesData, salt: codesSalt, aad: aadFor2FA()) else {
            return false
        }
        
        var combinedCodes = codesSalt
        combinedCodes.append(encryptedCodes)
        
        // Store enabled flag (just a marker, encrypted empty data)
        let enabledData = Data("enabled".utf8)
        let enabledSalt = generateSalt()
        guard let encryptedEnabled = CryptoHelper.encryptPasswordData(enabledData, salt: enabledSalt, aad: aadFor2FA()) else {
            return false
        }
        
        var combinedEnabled = enabledSalt
        combinedEnabled.append(encryptedEnabled)
        
        // Save to keychain
        return saveEncryptedToKeychain(combinedSecret, key: secretKey) &&
               saveEncryptedToKeychain(combinedCodes, key: backupCodesKey) &&
               saveEncryptedToKeychain(combinedEnabled, key: enabledKey)
    }
    
    /// Disable 2FA (requires master password verification)
    func disable(masterPassword: Data, context: NSManagedObjectContext) async -> Bool {
        guard await CryptoHelper.verifyMasterPassword(password: masterPassword, context: context) else {
            return false
        }
        
        // Delete from keychain
        deleteFromKeychain(key: secretKey)
        deleteFromKeychain(key: backupCodesKey)
        deleteFromKeychain(key: enabledKey)
        
        return true
    }
    
    // MARK: - Verification
    
    /// Verify a TOTP code
    func verify(code: String, masterPassword: Data) -> Bool {
        guard isEnabled else { return true } // 2FA not enabled, always pass
        
        // Try TOTP verification
        if verifyTOTP(code: code, masterPassword: masterPassword) {
            return true
        }
        
        // Try backup code verification
        return verifyBackupCode(code: code, masterPassword: masterPassword)
    }
    
    private func verifyTOTP(code: String, masterPassword: Data) -> Bool {
        guard let secret = getDecryptedSecret(masterPassword: masterPassword) else {
            return false
        }
        
        // Get current time-based code
        let currentTime = Date().timeIntervalSince1970
        let timeSlice = Int(currentTime / 30) // 30-second time window
        
        // Check current time slice and ±1 to account for clock skew
        for offset in -1...1 {
            let testCode = generateTOTP(secret: secret, timeSlice: timeSlice + offset)
            if constantTimeCompare(code, testCode) {
                return true
            }
        }
        
        return false
    }
    
    private func verifyBackupCode(code: String, masterPassword: Data) -> Bool {
        guard var backupCodes = getDecryptedBackupCodes(masterPassword: masterPassword) else {
            return false
        }
        
        // Check if code exists
        guard let index = backupCodes.firstIndex(where: { constantTimeCompare($0, code) }) else {
            return false
        }
        
        // Remove used backup code
        backupCodes.remove(at: index)
        
        // Re-encrypt and save remaining codes
        let codesData = Data(backupCodes.joined(separator: ",").utf8)
        let salt = generateSalt()
        guard let encrypted = CryptoHelper.encryptPasswordData(codesData, salt: salt, aad: aadFor2FA()) else {
            return false
        }
        
        var combined = salt
        combined.append(encrypted)
        
        return saveEncryptedToKeychain(combined, key: backupCodesKey)
    }
    
    // MARK: - Backup Codes Management
    
    func getRemainingBackupCodes(masterPassword: Data) -> [String]? {
        return getDecryptedBackupCodes(masterPassword: masterPassword)
    }
    
    func regenerateBackupCodes(masterPassword: Data) -> [String]? {
        guard CryptoHelper.keyStorage != nil else {
            return nil
        }
        
        let newCodes = generateBackupCodes(count: 10)
        let codesData = Data(newCodes.joined(separator: ",").utf8)
        let salt = generateSalt()
        
        guard let encrypted = CryptoHelper.encryptPasswordData(codesData, salt: salt, aad: aadFor2FA()) else {
            return nil
        }
        
        var combined = salt
        combined.append(encrypted)
        
        guard saveEncryptedToKeychain(combined, key: backupCodesKey) else {
            return nil
        }
        
        return newCodes
    }
    
    // MARK: - TOTP Generation
    
    private func generateTOTP(secret: String, timeSlice: Int) -> String {
        guard let secretData = base32Decode(secret) else {
            return ""
        }
        
        // Convert time slice to 8-byte big-endian
        var counter = UInt64(timeSlice).bigEndian
        let counterData = Data(bytes: &counter, count: 8)
        
        // HMAC-SHA1
        let key = SymmetricKey(data: secretData)
        let hmac = HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: key)
        let hmacData = Data(hmac)
        
        // Dynamic truncation
        let offset = Int(hmacData[hmacData.count - 1] & 0x0f)
        let truncatedHash = hmacData.subdata(in: offset..<offset + 4)
        
        var value = UInt32(bigEndian: truncatedHash.withUnsafeBytes { $0.load(as: UInt32.self) })
        value &= 0x7fffffff
        value %= 1_000_000
        
        return String(format: "%06d", value)
    }
    
    // MARK: - Encrypted Storage Helpers
    
    private func getDecryptedSecret(masterPassword: Data) -> String? {
        guard let combined = loadEncryptedFromKeychain(key: secretKey),
              combined.count > 32 else {
            return nil
        }
        
        let salt = combined.prefix(32)
        let encrypted = combined.dropFirst(32)
        
        guard let decrypted = CryptoHelper.decryptPasswordData(encrypted, salt: salt, aad: aadFor2FA()) else {
            return nil
        }
        
        return String(data: decrypted, encoding: .utf8)
    }
    
    private func getDecryptedBackupCodes(masterPassword: Data) -> [String]? {
        guard let combined = loadEncryptedFromKeychain(key: backupCodesKey),
              combined.count > 32 else {
            return nil
        }
        
        let salt = combined.prefix(32)
        let encrypted = combined.dropFirst(32)
        
        guard let decrypted = CryptoHelper.decryptPasswordData(encrypted, salt: salt, aad: aadFor2FA()),
              let codesString = String(data: decrypted, encoding: .utf8) else {
            return nil
        }
        
        return codesString.split(separator: ",").map { String($0) }
    }
    
    // MARK: - Helper Functions
    
    private func generateBackupCodes(count: Int) -> [String] {
        var codes: [String] = []
        
        for _ in 0..<count {
            var codeData = Data(count: 4)
            _ = codeData.withUnsafeMutableBytes { buffer in
                SecRandomCopyBytes(kSecRandomDefault, 4, buffer.baseAddress!)
            }
            
            let code = codeData.map { String(format: "%02x", $0) }.joined()
            codes.append(code)
        }
        
        return codes
    }
    
    private func generateSalt() -> Data {
        var salt = Data(count: 32)
        _ = salt.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, 32, buffer.baseAddress!)
        }
        return salt
    }
    
    private func aadFor2FA() -> Data {
        return Data("2fa-auth-v1".utf8)
    }
    
    private func constantTimeCompare(_ a: String, _ b: String) -> Bool {
        guard a.count == b.count else { return false }
        
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        
        var result = 0
        for i in 0..<aBytes.count {
            result |= Int(aBytes[i]) ^ Int(bBytes[i])
        }
        
        return result == 0
    }
    
    // MARK: - Keychain Operations (Raw, for encrypted data)
    
    private func saveEncryptedToKeychain(_ data: Data, key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false
        ]
        
        SecItemDelete(query as CFDictionary)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }
    
    private func loadEncryptedFromKeychain(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess ? (result as? Data) : nil
    }
    
    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    // MARK: - Base32 Encoding/Decoding
    
    private func base32Encode(_ data: Data) -> String {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        var result = ""
        var bits = 0
        var buffer = 0
        
        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            
            while bits >= 5 {
                bits -= 5
                let index = (buffer >> bits) & 0x1F
                result.append(alphabet[alphabet.index(alphabet.startIndex, offsetBy: index)])
            }
        }
        
        if bits > 0 {
            buffer <<= (5 - bits)
            let index = buffer & 0x1F
            result.append(alphabet[alphabet.index(alphabet.startIndex, offsetBy: index)])
        }
        
        return result
    }
    
    private func base32Decode(_ string: String) -> Data? {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        var result = Data()
        var bits = 0
        var buffer = 0
        
        for char in string.uppercased() {
            guard let index = alphabet.firstIndex(of: char) else { continue }
            let value = alphabet.distance(from: alphabet.startIndex, to: index)
            
            buffer = (buffer << 5) | value
            bits += 5
            
            if bits >= 8 {
                bits -= 8
                result.append(UInt8((buffer >> bits) & 0xFF))
            }
        }
        
        return result
    }
}
