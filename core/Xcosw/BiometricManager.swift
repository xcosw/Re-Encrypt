import SwiftUI
import AppKit
import LocalAuthentication
import CryptoKit
import Security
import SystemConfiguration
internal import Combine

@MainActor
class BiometricManager: NSObject, ObservableObject {
    static let shared = BiometricManager()
    
    @Published var isBiometricAvailable = false
    @Published var biometricType: LABiometryType = .none
    @Published var isPasswordStored = false
    
    private let maxBiometricAttempts = 3
    @AppStorage("BiometricFailedAttempts") private var failedBiometricAttempts: Int = 0
    private var lastBiometricAttempt: Date?
    private let biometricCooldown: TimeInterval = 1.0
    private let queue = DispatchQueue(label: "com.biometric.queue", qos: .userInitiated)
    
    private var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let bundleID = Bundle.main.bundleIdentifier ?? "com.password-manager"
        let folder = appSupport.appendingPathComponent(bundleID).appendingPathComponent(".biometric", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return folder
    }
    
    private var passwordFileURL: URL {
        storageURL.appendingPathComponent("biometric-password.enc")
    }
    
    private var keyFileURL: URL {
        storageURL.appendingPathComponent("biometric-key.enc")
    }
    
    override init() {
        super.init()
        checkBiometricAvailability()
        checkIfPasswordStored()
    }
    
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
    @MainActor
    private func deviceBoundAAD() -> Data {
        var aad = Data("biometric-v2".utf8)
        aad.append(getDeviceID())
        return aad
    }
    
    // MARK: - Biometric Status
    
    func checkBiometricAvailability() {
        let context = LAContext()
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isBiometricAvailable = canEvaluate
            self.biometricType = context.biometryType
            print("[BiometricManager] Available: \(canEvaluate), Type: \(context.biometryType.rawValue)")
        }
    }
    
    func checkIfPasswordStored() {
        let stored = FileManager.default.fileExists(atPath: passwordFileURL.path)
        DispatchQueue.main.async { [weak self] in
            self?.isPasswordStored = stored
            print("[BiometricManager] Password stored: \(stored)")
        }
    }
    
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
    
    // MARK: - Password Storage
    
    func storeMasterPassword(_ password: Data) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            print("[BiometricManager] 🔐 Storing password with device binding...")
            
            do {
                let encryptionKey = try self.getOrCreateEncryptionKey()
                
                // Encrypt with device-bound AAD
                let aad = self.deviceBoundAAD()
                let sealedBox = try AES.GCM.seal(password, using: encryptionKey, authenticating: aad)
                
                guard let combined = sealedBox.combined else {
                    throw BiometricError.unknown
                }
                
                // Add HMAC for integrity
                let deviceID = self.getDeviceID()
                let hmacKey = SymmetricKey(data: deviceID.prefix(32))
                let hmac = HMAC<SHA256>.authenticationCode(for: combined, using: hmacKey)
                
                var finalData = Data(hmac)
                finalData.append(combined)
                
                print("[BiometricManager] 📦 Password encrypted: \(finalData.count) bytes")
                
                // Save to file
                try finalData.write(to: self.passwordFileURL, options: [.atomic, .completeFileProtection])
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: self.passwordFileURL.path)
                
                DispatchQueue.main.async {
                    self.isPasswordStored = true
                    print("[BiometricManager] ✅ Password stored (device-bound)")
                }
                
            } catch {
                print("[BiometricManager] ❌ Storage failed: \(error)")
                DispatchQueue.main.async {
                    self.isPasswordStored = false
                }
            }
        }
    }
    
    func storeMasterPasswordSecure(_ password: Data) {
        var passwordCopy = password
        defer { passwordCopy.secureClear() }
        storeMasterPassword(passwordCopy)
    }
    
    // MARK: - Password Retrieval
    
    func retrieveMasterPassword(completion: @escaping (Result<Data, BiometricError>) -> Void) {
        queue.async { [weak self] in
            guard let self = self else {
                completion(.failure(.unknown))
                return
            }
            
            print("[BiometricManager] 📂 Retrieving password...")
            
            guard FileManager.default.fileExists(atPath: self.passwordFileURL.path) else {
                print("[BiometricManager] ❌ No stored password file")
                DispatchQueue.main.async {
                    completion(.failure(.unavailable("No stored password")))
                }
                return
            }
            
            // Prompt for biometric FIRST
            DispatchQueue.main.async {
                self.promptBiometric { [weak self] success in
                    guard let self = self else { return }
                    
                    if success {
                        self.decryptStoredPassword(completion: completion)
                    } else {
                        print("[BiometricManager] ❌ Biometric cancelled")
                        completion(.failure(.cancelled))
                    }
                }
            }
        }
    }
    
    private func decryptStoredPassword(completion: @escaping (Result<Data, BiometricError>) -> Void) {
        queue.async { [weak self] in
            guard let self = self else {
                completion(.failure(.unknown))
                return
            }
            
            print("[BiometricManager] 🔓 Decrypting password...")
            
            do {
                let finalData = try Data(contentsOf: self.passwordFileURL)
                
                guard finalData.count > 32 else {
                    throw BiometricError.unknown
                }
                
                // Verify HMAC
                let storedHMAC = finalData.prefix(32)
                let encryptedData = finalData.dropFirst(32)
                
                let deviceID = self.getDeviceID()
                let hmacKey = SymmetricKey(data: deviceID.prefix(32))
                let computedHMAC = HMAC<SHA256>.authenticationCode(for: encryptedData, using: hmacKey)
                
                guard self.constantTimeCompare(Data(storedHMAC), Data(computedHMAC)) else {
                    print("[BiometricManager] ❌ HMAC verification failed - possible device mismatch")
                    throw BiometricError.unknown
                }
                
                // Decrypt
                let encryptionKey = try self.getOrCreateEncryptionKey()
                let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
                let aad = self.deviceBoundAAD()
                let decryptedPassword = try AES.GCM.open(sealedBox, using: encryptionKey, authenticating: aad)
                
                print("[BiometricManager] ✅ Password decrypted (device verified)")
                DispatchQueue.main.async {
                    completion(.success(decryptedPassword))
                }
                
            } catch {
                print("[BiometricManager] ❌ Decryption failed: \(error)")
                DispatchQueue.main.async {
                    completion(.failure(.unknown))
                }
            }
        }
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
    
    // MARK: - Biometric Prompt
    
    private func promptBiometric(completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        context.localizedReason = "Unlock your password manager"
        context.localizedFallbackTitle = "Use Master Password"
        
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            print("[BiometricManager] ❌ Biometric not available")
            completion(false)
            return
        }
        
        print("[BiometricManager] 👆 Prompting for biometric...")
        
        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Authenticate to unlock your password manager"
        ) { success, authError in
            DispatchQueue.main.async {
                if success {
                    print("[BiometricManager] ✅ Biometric authenticated")
                } else {
                    print("[BiometricManager] ❌ Biometric failed")
                }
                completion(success)
            }
        }
    }
    
    // MARK: - Clear Password
    
    func clearStoredPassword() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // Secure overwrite
            for url in [self.passwordFileURL, self.keyFileURL] {
                if FileManager.default.fileExists(atPath: url.path) {
                    if let handle = try? FileHandle(forWritingTo: url) {
                        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
                        var randomData = Data(count: Int(size))
                        _ = randomData.withUnsafeMutableBytes {
                            SecRandomCopyBytes(kSecRandomDefault, Int(size), $0.baseAddress!)
                        }
                        handle.write(randomData)
                        try? handle.close()
                    }
                    try? FileManager.default.removeItem(at: url)
                }
            }
            
            DispatchQueue.main.async {
                self.isPasswordStored = false
                print("[BiometricManager] ✅ Password and key securely cleared")
            }
        }
    }
    
    func clearStoredPasswordSecure() {
        clearStoredPassword()
    }
    
    // MARK: - Public Authenticate
    
    func authenticate(completion: @escaping (Result<Data, BiometricError>) -> Void) {
        // Rate limiting
        if let last = lastBiometricAttempt, Date().timeIntervalSince(last) < biometricCooldown {
            completion(.failure(.unavailable("Please wait")))
            return
        }
        lastBiometricAttempt = Date()
        
        // Check attempts
        if failedBiometricAttempts >= maxBiometricAttempts {
            completion(.failure(.lockout))
            return
        }
        
        if !isPasswordStored {
            completion(.failure(.unavailable("No stored password")))
            return
        }
        
        retrieveMasterPassword { [weak self] result in
            switch result {
            case .success(let data):
                self?.failedBiometricAttempts = 0
                completion(.success(data))
            case .failure(let error):
                self?.failedBiometricAttempts += 1
                
                if self?.failedBiometricAttempts ?? 0 >= self?.maxBiometricAttempts ?? 3 {
                    self?.clearStoredPasswordSecure()
                }
                
                completion(.failure(error))
            }
        }
    }
    
    func resetFailedAttempts() {
        failedBiometricAttempts = 0
        lastBiometricAttempt = nil
    }
    
    func forceResetLockout() {
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
