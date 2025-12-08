


import SwiftUI
import LocalAuthentication
import CryptoKit
internal import Combine

@MainActor
final class BiometricManager: ObservableObject {
    static let shared = BiometricManager()
    
    @Published var isBiometricAvailable = false
    @Published var biometricType: LABiometryType = .none
    @Published var isPasswordStored = false
    
    private let maxBiometricAttempts = 3
    @AppStorage("BiometricFailedAttempts") private var failedBiometricAttempts = 0
    private var lastBiometricAttempt: Date?
    private let biometricCooldown: TimeInterval = 1.0
    
    private let fileManager = FileManager.default
    private lazy var storageURL: URL = {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let bundleID = Bundle.main.bundleIdentifier ?? "com.xcosw.reencrypt"
        let folder = appSupport.appendingPathComponent(bundleID).appendingPathComponent(".biometric", isDirectory: true)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return folder
    }()
    
    private var passwordFileURL: URL { storageURL.appendingPathComponent("biometric-password.enc") }
    private var keyFileURL: URL { storageURL.appendingPathComponent("biometric-key.enc") }
    
    private init() {
        checkBiometricAvailability()
        checkIfPasswordStored()
    }
    
    // MARK: - Public Authenticate (THE ONE YOU CALL)
    func authenticate() async -> Result<Data, BiometricError> {
        // Rate limiting
        if let last = lastBiometricAttempt,
           Date().timeIntervalSince(last) < biometricCooldown {
            return .failure(.unavailable("Please wait"))
        }
        lastBiometricAttempt = Date()
        
        // Lockout
        if failedBiometricAttempts >= maxBiometricAttempts {
            return .failure(.lockout)
        }
        
        // No stored password
        if !isPasswordStored {
            return .failure(.unavailable("No password stored"))
        }
        
        // Perform biometric + retrieval
        let result = await retrieveMasterPassword()
        
        switch result {
        case .success:
            failedBiometricAttempts = 0
        case .failure:
            failedBiometricAttempts += 1
            if failedBiometricAttempts >= maxBiometricAttempts {
                await clearStoredPasswordSecure()
                return .failure(.lockout)
            }
        }
        
        return result
    }
    
    // MARK: - Core Biometric + Retrieval
    private func retrieveMasterPassword() async -> Result<Data, BiometricError> {
        // Step 1: Prompt biometric
        let biometricSuccess = await promptBiometric()
        guard biometricSuccess else {
            return .failure(.cancelled)
        }
        
        // Step 2: Decrypt stored password
        return await decryptStoredPassword()
    }
    
    private func promptBiometric() async -> Bool {
        await withCheckedContinuation { continuation in
            let context = LAContext()
            context.localizedReason = "Unlock re:Encrypt"
            context.localizedFallbackTitle = "Use Master Password"
            
            var error: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
                continuation.resume(returning: false)
                return
            }
            
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: context.localizedReason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
    
    @MainActor
    private func decryptStoredPassword() async -> Result<Data, BiometricError> {
        // Run decryption off the main thread — it's CPU-heavy
        return await withCheckedContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                do {
                    guard await FileManager.default.fileExists(atPath: self.passwordFileURL.path) else {
                        continuation.resume(returning: .failure(.unavailable("No stored password")))
                        return
                    }
                    
                    let finalData = try await Data(contentsOf: self.passwordFileURL)
                    guard finalData.count > 32 else {
                        continuation.resume(returning: .failure(.unknown))
                        return
                    }
                    
                    let storedHMAC = finalData.prefix(32)
                    let encryptedData = finalData.dropFirst(32)
                    
                    let deviceID = await self.getDeviceID()
                    let hmacKey = SymmetricKey(data: deviceID.prefix(32))
                    let computedHMAC = HMAC<SHA256>.authenticationCode(for: encryptedData, using: hmacKey)
                    
                    guard await self.constantTimeCompare(Data(storedHMAC), Data(computedHMAC)) else {
                        continuation.resume(returning: .failure(.unknown))
                        return
                    }
                    
                    let encryptionKey = try await self.getOrCreateEncryptionKey()
                    let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
                    let aad = await self.deviceBoundAAD()
                    
                    let password = try AES.GCM.open(sealedBox, using: encryptionKey, authenticating: aad)
                    
                    continuation.resume(returning: .success(password))
                    
                } catch {
                    continuation.resume(returning: .failure(.unknown))
                }
            }
        }
    }
    
    // MARK: - Device Binding (unchanged — perfect)
    // MARK: - Device Binding
    private func getDeviceID() -> Data {
        var components = [String]()
        
        // Hardware UUID
        let platformExpert = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(platformExpert) }
        
        if platformExpert != 0 {
            if let cfUUID = IORegistryEntryCreateCFProperty(platformExpert, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?.takeUnretainedValue() as? String {
                components.append(cfUUID)
            }
        }
        
        // Username
        let username = NSUserName()
        if !username.isEmpty {
            components.append(username)
        }
        
        // Stable device salt
        let deviceSaltKey = "com.app.device-salt.biometric"
        let deviceSalt: String
        if let existing = UserDefaults.standard.string(forKey: deviceSaltKey) {
            deviceSalt = existing
        } else {
            var randomData = Data(count: 32)
            _ = randomData.withUnsafeMutableBytes {
                SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
            }
            deviceSalt = randomData.base64EncodedString()
            UserDefaults.standard.set(deviceSalt, forKey: deviceSaltKey)
        }
        components.append(deviceSalt)
        
        let combined = components.joined(separator: "|")
        let hash = SHA256.hash(data: Data(combined.utf8))
        return Data(hash)
    }

    private func deviceBoundAAD() -> Data {
        var aad = Data("biometric-v2".utf8)
        aad.append(getDeviceID())
        return aad
    }
    
    // MARK: - Encryption Key Management
    
    private func getOrCreateEncryptionKey() throws -> SymmetricKey {
        // Check if key file exists
        if FileManager.default.fileExists(atPath: keyFileURL.path) {
            let encryptedKeyData = try Data(contentsOf: keyFileURL)
            
            // Decrypt with device binding
            let deviceID = getDeviceID()
            let deviceKey = SymmetricKey(data: deviceID)
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedKeyData)
            let aad = Data("key-storage-v2".utf8) + deviceID
            let keyData = try AES.GCM.open(sealedBox, using: deviceKey, authenticating: aad)
            
            print("[BiometricManager] ✅ Encryption key loaded (device-bound)")
            return SymmetricKey(data: keyData)
        }
        
        // Create new key
        print("[BiometricManager] 🔑 Creating new encryption key...")
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        
        // Encrypt with device binding before storing
        let deviceID = getDeviceID()
        let deviceKey = SymmetricKey(data: deviceID)
        let aad = Data("key-storage-v2".utf8) + deviceID
        let sealedBox = try AES.GCM.seal(keyData, using: deviceKey, authenticating: aad)
        
        guard let combined = sealedBox.combined else {
            throw BiometricError.unknown
        }
        
        // Save encrypted key
        try combined.write(to: keyFileURL, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyFileURL.path)
        
        print("[BiometricManager] ✅ Encryption key created (device-bound)")
        return newKey
    }
    
    private func constantTimeCompare(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        return a.withUnsafeBytes { aBytes in
            b.withUnsafeBytes { bBytes in
                var result = 0
                for i in 0..<a.count {
                    result |= Int(aBytes[i]) ^ Int(bBytes[i])
                }
                return result == 0
            }
        }
    }
    
    
    // MARK: - Storage
    func storeMasterPasswordSecure(_ password: Data) {
        let secured = password // Take ownership
        
        Task.detached(priority: .userInitiated) {
            await self.storeMasterPassword(secured)
            // `secured` lives only in this task → automatically destroyed
        }
        
        // Immediately wipe the input
        var input = password
        input.secureWipe()
    }
    
    private func storeMasterPassword(_ password: Data) async {
        do {
            let key = try getOrCreateEncryptionKey()
            let aad = deviceBoundAAD()
            let sealed = try AES.GCM.seal(password, using: key, authenticating: aad)
            guard let combined = sealed.combined else { throw BiometricError.unknown }
            
            let deviceID = getDeviceID()
            let hmacKey = SymmetricKey(data: deviceID.prefix(32))
            let hmac = HMAC<SHA256>.authenticationCode(for: combined, using: hmacKey)
            
            var finalData = Data(hmac)
            finalData.append(combined)
            
            try finalData.write(to: passwordFileURL, options: [.atomic, .completeFileProtection])
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: passwordFileURL.path)
            
            await MainActor.run {
                isPasswordStored = true
            }
        } catch {
            await MainActor.run { isPasswordStored = false }
        }
    }
    
    func clearStoredPasswordSecure() async {
        Task.detached(priority: .high) {
            await self.clearStoredPassword()
        }
    }
    
    private func clearStoredPassword() async {
        for url in [passwordFileURL, keyFileURL] {
            if fileManager.fileExists(atPath: url.path) {
                try? Data(count: 4096).write(to: url) // overwrite
                try? fileManager.removeItem(at: url)
            }
        }
        await MainActor.run {
            isPasswordStored = false
            failedBiometricAttempts = 0
        }
    }
    
    // MARK: - Helpers
    func checkBiometricAvailability() {
        let context = LAContext()
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

        // Already on @MainActor – safe to update @Published variables
        self.isBiometricAvailable = canEvaluate
        self.biometricType = context.biometryType

        print("[BiometricManager] Available: \(canEvaluate), Type: \(context.biometryType.rawValue)")
    }
    func checkIfPasswordStored() { isPasswordStored = fileManager.fileExists(atPath: passwordFileURL.path) }
    func biometricDisplayName() -> String {
        switch biometricType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        case .none: return "Biometric"
        @unknown default: return "Biometric"
        }
    }
    
    func biometricSystemImage() -> String {
        switch biometricType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        case .none: return "lock.fill"
        @unknown default: return "lock.fill"
        }
    }
    
    func resetFailedAttempts() {
        failedBiometricAttempts = 0
        lastBiometricAttempt = nil
    }
}
    
    
  
enum BiometricError: LocalizedError {
    case unavailable(String)
    case cancelled
    case fallback
    case lockout
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): return reason
        case .cancelled: return "Cancelled"
        case .fallback: return "Use master password"
        case .lockout: return "Too many attempts"
        case .unknown: return "Authentication failed"
        }
    }
}
