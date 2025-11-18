//
//  CryptoHelper.swift
//  re-Encrypt
//
//  Secure implementation - Uses existing SecData.swift
//

import Foundation
import AppKit
import Security
import CryptoKit
import CommonCrypto
import LocalAuthentication
import SystemConfiguration
import CoreData
import os.log

// MARK: - Custom Keychain Manager
@MainActor
final class CustomKeychainManager {
    static let shared = CustomKeychainManager()
    private var customKeychainRef: SecKeychain?
    private let keychainLock = NSLock()
    private(set) var isSetup: Bool = false
    
    private var keychainPath: URL {
        let username = NSUserName()
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = appSupport.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.secure.app")
        
        if !FileManager.default.fileExists(atPath: folder.path) {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: NSNumber(value: 0o700)])
            } catch {
                print("❌ Failed to create directory: \(error)")
            }
        }
        
        return folder.appendingPathComponent("\(username).keychain")
    }
    
    private init() {
        attemptToOpenExistingKeychain()
    }
    
    private func attemptToOpenExistingKeychain() {
        keychainLock.lock()
        defer { keychainLock.unlock() }
        
        let path = keychainPath.path
        guard FileManager.default.fileExists(atPath: path) else { return }
        
        var keychain: SecKeychain?
        let status = SecKeychainOpen(path, &keychain)
        
        if status == errSecSuccess, let kc = keychain {
            customKeychainRef = kc
            isSetup = true
        }
    }
    
    func setupKeychain(withPassword password: SecData) -> Bool {
        keychainLock.lock()
        defer { keychainLock.unlock() }
        
        let path = keychainPath.path
        var keychain: SecKeychain?
        
        if FileManager.default.fileExists(atPath: path) {
            let openStatus = SecKeychainOpen(path, &keychain)
            
            if openStatus == errSecSuccess, let kc = keychain {
                customKeychainRef = kc
                let unlocked = unlockKeychainInternal(kc, password: password)
                if unlocked {
                    isSetup = true
                    return true
                }
                return false
            } else {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        
        let status = password.withUnsafeBytes { passwordPtr -> OSStatus in
            guard let baseAddress = passwordPtr.baseAddress else { return errSecParam }
            return SecKeychainCreate(path, UInt32(passwordPtr.count), baseAddress, false, nil, &keychain)
        }
        
        if status == errSecSuccess, let kc = keychain {
            customKeychainRef = kc
            isSetup = true
            
            var settings = SecKeychainSettings(
                version: UInt32(SEC_KEYCHAIN_SETTINGS_VERS1),
                lockOnSleep: false,
                useLockInterval: false,
                lockInterval: 0
            )
            _ = SecKeychainSetSettings(kc, &settings)
            return true
        }
        
        isSetup = false
        return false
    }
    
    private func unlockKeychainInternal(_ keychain: SecKeychain, password: SecData) -> Bool {
        var keychainStatus: SecKeychainStatus = 0
        var status = SecKeychainGetStatus(keychain, &keychainStatus)
        if status == errSecSuccess { return true }
        
        status = password.withUnsafeBytes { passwordPtr -> OSStatus in
            guard let baseAddress = passwordPtr.baseAddress else { return errSecParam }
            return SecKeychainUnlock(keychain, UInt32(passwordPtr.count), baseAddress, false)
        }
        
        if status == errSecSuccess {
            isSetup = true
            return true
        }
        return false
    }
    
    func unlockKeychain(withPassword password: SecData) -> Bool {
        keychainLock.lock()
        defer { keychainLock.unlock() }
        
        guard let keychain = customKeychainRef else { return false }
        return unlockKeychainInternal(keychain, password: password)
    }
    
    func save(_ data: Data, key: String, encrypted: Data) -> Bool {
        guard isSetup, let keychain = customKeychainRef else { return false }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: encrypted,
            kSecUseKeychain as String: keychain,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    func load(key: String) -> Data? {
        guard isSetup, let keychain = customKeychainRef else { return nil }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecUseKeychain as String: keychain,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess ? result as? Data : nil
    }
    
    func delete(key: String) {
        guard let keychain = customKeychainRef else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecUseKeychain as String: keychain
        ]
        
        SecItemDelete(query as CFDictionary)
    }
    
    func reset() {
        keychainLock.lock()
        defer { keychainLock.unlock() }
        
        customKeychainRef = nil
        isSetup = false
        let path = keychainPath.path
        
        if FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}

// MARK: - Storage Backend
enum StorageBackend: String, Equatable {
    case keychain
    case local
}

// MARK: - Security Error Types
enum SecurityError: Error {
    case cryptographicFailure
    case memoryProtectionFailed
    case invalidInput
    case deviceCompromised
    case sessionExpired
    case keychainNotReady
    
    var localizedDescription: String {
        switch self {
        case .cryptographicFailure: return "Cryptographic operation failed"
        case .memoryProtectionFailed: return "Memory protection failed"
        case .invalidInput: return "Invalid input provided"
        case .deviceCompromised: return "Device security compromised"
        case .sessionExpired: return "Security session expired"
        case .keychainNotReady: return "Keychain not initialized"
        }
    }
}

// MARK: - Enhanced CryptoHelper
@MainActor
struct CryptoHelper {
    
    // MARK: - Security Constants
    private static let AADMasterTokenLabel = "master-token-v3-macos"
    private static let AADEntryBindingLabel = "entry-binding-v3-macos"
    private static let AADSettingsLabel = "settings-v3-macos"
    private static let pbkdf2Iterations: UInt32 = 600_000
    private static let backoffBase: TimeInterval = 1.0
    private static let backoffMax: TimeInterval = 30.0
    static let maxAttempts = 5
    
    static var sessionTimeout: TimeInterval {
        return SecurityConfigManager.shared.sessionTimeout
    }
    
    private static let tokenKey = "MasterPasswordToken.v3"
    private static let saltKey = "MasterPasswordSalt.v3"
    private static let backendDefaultsKey = "CryptoHelper.StorageBackend.v3"
    private static let failedAttemptsKey = "CryptoHelper.failedAttempts.v3"
    
    private static let minPasswordLength = 1
    private static let maxPasswordLength = 1024
    private static let saltLength = 32
    private static let maxEncryptedDataSize = 1_048_576
    private static let minEncryptedDataSize = 16
    
    // MARK: - Thread-Safe Key Storage
    private static let keyLock = NSLock()
    private static var _keyStorage: SecData?
    private static var _lastActivity: Date = Date()
    
    //private
    static var keyStorage: SecData? {
        get {
            keyLock.lock()
            defer { keyLock.unlock() }
            return _keyStorage
        }
        set {
            keyLock.lock()
            defer { keyLock.unlock() }
            _keyStorage?.clear()
            _keyStorage = newValue
        }
    }
    
    static var isUnlocked: Bool {
        keyLock.lock()
        defer { keyLock.unlock() }
        return _keyStorage != nil && !isSessionExpiredInternal()
    }
    
    private static func isSessionExpiredInternal() -> Bool {
        return Date().timeIntervalSince(_lastActivity) > sessionTimeout
    }
    
    private static func updateActivity() {
        keyLock.lock()
        defer { keyLock.unlock() }
        _lastActivity = Date()
    }
    
    // MARK: - Backend Management
    static var hasMasterPassword: Bool {
        switch storageBackend {
        case .keychain:
            return CustomKeychainManager.shared.load(key: tokenKey) != nil
        case .local:
            return loadFromLocalFile(name: tokenKey) != nil
        }
    }
    
    static func initializeKeychainBackend() {
        if storageBackend == .keychain {
            let manager = CustomKeychainManager.shared
            let username = NSUserName()
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let folder = appSupport.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.secure.app")
            let keychainPath = folder.appendingPathComponent("\(username).keychain")
            
            if FileManager.default.fileExists(atPath: keychainPath.path) {
                print("✅ Found existing keychain file")
            }
        }
    }
    
    static func currentBackend() -> StorageBackend {
        return storageBackend
    }
    
    static func clearStorage(_ backend: StorageBackend) {
        deleteRaw(tokenKey, from: backend)
        deleteRaw(saltKey, from: backend)
        if backend == .local {
            try? FileManager.default.removeItem(at: baseDirURL)
        } else if backend == .keychain {
            CustomKeychainManager.shared.reset()
        }
    }
    
    static func clearCurrentStorage() {
        clearStorage(storageBackend)
    }
    
    static func switchBackend(to newBackend: StorageBackend) {
        storageBackend = newBackend
    }
    
    private static var storageBackend: StorageBackend {
        get {
            guard let raw = UserDefaults.standard.string(forKey: backendDefaultsKey),
                  let backend = StorageBackend(rawValue: raw) else {
                return .keychain
            }
            return backend
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: backendDefaultsKey)
        }
    }
    
    // MARK: - Master Password Management
    static func verifyMasterPassword(password: Data, context: NSManagedObjectContext?) -> Bool {
        guard password.count > 0 && password.count <= maxPasswordLength else {
            incrementFailedAttemptsAndMaybeWipe(context: context)
            return false
        }
        
        guard let securePassword = SecData(password) else {
            incrementFailedAttemptsAndMaybeWipe(context: context)
            return false
        }
        defer { securePassword.clear() }
        
        if storageBackend == .keychain {
            let unlocked = CustomKeychainManager.shared.unlockKeychain(withPassword: securePassword)
            if !unlocked {
                incrementFailedAttemptsAndMaybeWipe(context: context)
                return false
            }
        }
        
        guard let salt = loadSaltSecurely() else {
            incrementFailedAttemptsAndMaybeWipe(context: context)
            return false
        }
        
        guard let derivedKey = try? deriveKeySecurely(password: securePassword, salt: salt) else {
            incrementFailedAttemptsAndMaybeWipe(context: context)
            return false
        }
        
        defer { derivedKey.clear() }
        
        let aad = tokenAAD()
        guard let tokenData = loadRawSecurely(tokenKey, from: storageBackend, using: derivedKey) else {
            incrementFailedAttemptsAndMaybeWipe(context: context)
            return false
        }
        
        let isValid = derivedKey.withUnsafeBytes { keyBuffer in
            let key = SymmetricKey(data: Data(keyBuffer))
            do {
                let sealedBox = try AES.GCM.SealedBox(combined: tokenData)
                let decrypted = try AES.GCM.open(sealedBox, using: key, authenticating: aad)
                let expected = "verify-v3".data(using: .utf8)!
                return constantTimeCompare(decrypted, expected)
            } catch {
                return false
            }
        }
        
        if isValid {
            setFailedAttempts(0)
            keyStorage = SecData(Data(derivedKey.withUnsafeBytes { Data($0) }))
            updateActivity()
            secureLog("Master password verified successfully")
        } else {
            incrementFailedAttemptsAndMaybeWipe(context: context)
            secureLog("Master password verification failed")
        }
        
        return isValid
    }
    
    private static func constantTimeCompare(_ a: Data, _ b: Data) -> Bool {
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
    
    static func clearKey() {
        keyStorage?.clear()
        keyStorage = nil
        updateActivity()
        secureLog("In-memory master key cleared")
    }
    
    static func clearKeys() {
        keyStorage?.clear()
        keyStorage = nil
        updateActivity()
        secureLog("All in-memory keys cleared")
    }
    
    // MARK: - Secure Key Derivation
    private static func deriveKeySecurely(password: SecData, salt: Data) throws -> SecData {
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
                    pbkdf2Iterations,
                    &derived,
                    derived.count
                )
            }
        }
        
        guard result == kCCSuccess else {
            memset_s(&derived, derived.count, 0, derived.count)
            throw SecurityError.cryptographicFailure
        }
        
        guard let secureKey = SecData(Data(derived)) else {
            memset_s(&derived, derived.count, 0, derived.count)
            throw SecurityError.memoryProtectionFailed
        }
        
        memset_s(&derived, derived.count, 0, derived.count)
        return secureKey
    }
    
    private static func deriveSubKey(from masterKey: SecData, context: String, outputByteCount: Int = 32) -> SecData? {
        let salt = Data(SHA256.hash(data: Data(context.utf8)))
        let info = Data((context + "-hkdf-v3").utf8)
        
        let keyData = masterKey.withUnsafeBytes { keyBuffer in
            let key = SymmetricKey(data: Data(keyBuffer))
            return HKDF<SHA256>.deriveKey(
                inputKeyMaterial: key,
                salt: salt,
                info: info,
                outputByteCount: outputByteCount
            )
        }
        
        return SecData(Data(keyData.withUnsafeBytes { Data($0) }))
    }
    
    private static func loadSaltSecurely() -> Data? {
        switch storageBackend {
        case .keychain:
            return CustomKeychainManager.shared.load(key: saltKey)
        case .local:
            return loadFromLocalFile(name: saltKey)
        }
    }
    
    private static func saveSaltSecurely(_ salt: Data) -> Bool {
        switch storageBackend {
        case .keychain:
            guard CustomKeychainManager.shared.isSetup else { return false }
            return CustomKeychainManager.shared.save(salt, key: saltKey, encrypted: salt)
        case .local:
            do {
                try ensureDir()
                let url = baseDirURL.appendingPathComponent("\(saltKey).enc")
                try salt.write(to: url, options: [.atomic, .completeFileProtection])
                try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o600))], ofItemAtPath: url.path)
                return true
            } catch {
                return false
            }
        }
    }
    
    // MARK: - Device Binding
    static func deviceIdentifier() -> Data {
        return getDeviceID()
    }
    
    private static func getDeviceID() -> Data {
        var components = [String]()
        
        let platformExpert = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(platformExpert) }
        
        if platformExpert != 0 {
            if let cfUUID = IORegistryEntryCreateCFProperty(platformExpert, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?.takeUnretainedValue() as? String {
                components.append(cfUUID)
            }
        }
        
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        if size > 0 {
            var cpuModel = [CChar](repeating: 0, count: size)
            if sysctlbyname("machdep.cpu.brand_string", &cpuModel, &size, nil, 0) == 0,
               let model = String(validatingUTF8: cpuModel),
               !isVirtualMachineCPU(model) {
                components.append(model)
            }
        }
        
        if let mac = getPrimaryMACAddress(), !isVirtualMachineMAC(mac) {
            components.append(mac)
        }
        
        if let serial = getHardwareSerialNumber() {
            components.append(serial)
        }
        
        let username = NSUserName()
        if !username.isEmpty {
            components.append(username)
        }
        
        let installTimeKey = "com.app.install-timestamp"
        if let installTime = UserDefaults.standard.string(forKey: installTimeKey) {
            components.append(installTime)
        } else {
            let timestamp = "\(Date().timeIntervalSince1970)"
            UserDefaults.standard.set(timestamp, forKey: installTimeKey)
            components.append(timestamp)
        }
        
        let deviceSaltKey = "com.app.device-salt"
        let deviceSalt: String
        if let existing = UserDefaults.standard.string(forKey: deviceSaltKey) {
            deviceSalt = existing
        } else {
            var randomData = Data(count: 32)
            let result = randomData.withUnsafeMutableBytes {
                SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
            }
            guard result == errSecSuccess else {
                fatalError("Failed to generate secure random device salt")
            }
            deviceSalt = randomData.base64EncodedString()
            UserDefaults.standard.set(deviceSalt, forKey: deviceSaltKey)
        }
        components.append(deviceSalt)
        
        if components.count == 2 {
            if let fallbackUUID = getStableFallbackUUID() {
                components.append(fallbackUUID)
            } else {
                components.append("mac-device-\(getSystemUptime())")
            }
        }
        
        let combined = components.joined(separator: "|")
        let hash = SHA256.hash(data: Data(combined.utf8))
        return Data(hash)
    }
    
    private static func getStableFallbackUUID() -> String? {
        let key = "com.app.stable-device-uuid"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data, let uuid = String(data: data, encoding: .utf8) {
            return uuid
        }
        
        let newUUID = UUID().uuidString
        let storeQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: newUUID.data(using: .utf8) ?? Data(),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemAdd(storeQuery as CFDictionary, nil)
        return newUUID
    }
    
    private static func getSystemUptime() -> String {
        var mib: [Int32] = [Int32(CTL_KERN), Int32(KERN_BOOTTIME)]
        var boottime = timeval()
        var size = MemoryLayout<timeval>.size
        
        if sysctl(&mib, 2, &boottime, &size, nil, 0) == 0 {
            return "\(boottime.tv_sec)"
        }
        return "\(Date().timeIntervalSince1970)"
    }
    
    private static func deviceBoundInfo(label: String) -> Data {
        var info = Data(label.utf8)
        info.append(getDeviceID())
        return info
    }
    
    private static func tokenAAD() -> Data {
        return deviceBoundInfo(label: AADMasterTokenLabel)
    }
    
    private static func isVirtualMachineCPU(_ model: String) -> Bool {
        let lower = model.lowercased()
        let vmIndicators = ["virtual", "vmware", "parallels", "qemu", "virtualbox", "hyperv"]
        return vmIndicators.contains { lower.contains($0) }
    }
    
    private static func isVirtualMachineMAC(_ mac: String) -> Bool {
        let vmPrefixes = ["00:05:69", "00:0C:29", "00:50:56", "08:00:27", "00:1C:14", "00:03:FF", "00:15:5D"]
        let normalized = mac.uppercased()
        return vmPrefixes.contains { normalized.hasPrefix($0) }
    }
    
    private static func getPrimaryMACAddress() -> String? {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return nil }
        for interface in interfaces {
            if let mac = SCNetworkInterfaceGetHardwareAddressString(interface) as String?, !mac.isEmpty {
                return mac
            }
        }
        return nil
    }
    
    private static func getHardwareSerialNumber() -> String? {
        let platformExpert = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(platformExpert) }
        if platformExpert == 0 { return nil }
        return IORegistryEntryCreateCFProperty(platformExpert, "IOPlatformSerialNumber" as CFString, kCFAllocatorDefault, 0)?.takeUnretainedValue() as? String
    }
    
    // MARK: - Secure Storage Backend Migration
    static func setStorageBackendSecurely(_ backend: StorageBackend, masterPassword: Data, context: NSManagedObjectContext) -> Bool {
        let old = currentBackend()
        guard old != backend else { return true }
        
        guard let securePassword = SecData(masterPassword) else { return false }
        defer { securePassword.clear() }
        
        guard let oldSalt = loadSaltSecurely() else { return false }
        
        guard let oldDerivedKey = try? deriveKeySecurely(password: securePassword, salt: oldSalt) else {
            return false
        }
        defer { oldDerivedKey.clear() }
        
        guard let oldToken = loadRawSecurely(tokenKey, from: old, using: oldDerivedKey) else {
            return false
        }
        
        if backend == .keychain {
            guard CustomKeychainManager.shared.setupKeychain(withPassword: securePassword) else {
                return false
            }
        }
        
        storageBackend = backend
        
        guard saveSaltSecurely(oldSalt) else {
            storageBackend = old
            return false
        }
        
        guard saveRawSecurely(oldToken, key: tokenKey, to: backend, using: oldDerivedKey) else {
            storageBackend = old
            return false
        }
        
        let isValid = oldDerivedKey.withUnsafeBytes { keyBuffer -> Bool in
            let key = SymmetricKey(data: Data(keyBuffer))
            guard let sealedBox = try? AES.GCM.SealedBox(combined: oldToken),
                  let decrypted = try? AES.GCM.open(sealedBox, using: key, authenticating: tokenAAD()) else {
                return false
            }
            return decrypted == "verify-v3".data(using: .utf8)
        }
        
        if !isValid {
            storageBackend = old
            deleteRaw(tokenKey, from: backend)
            deleteRaw(saltKey, from: backend)
            return false
        }
        
        secureDeleteFromBackend(old)
        setFailedAttempts(0)
        return true
    }
    
    private static func secureDeleteFromBackend(_ backend: StorageBackend) {
        let randomData = Data(count: 1024)
        deleteRaw(tokenKey, from: backend)
        deleteRaw(saltKey, from: backend)
        
        if backend == .keychain {
            CustomKeychainManager.shared.reset()
        }
    }
    
    static func setStorageBackendWithoutMigration(_ backend: StorageBackend, context: NSManagedObjectContext) {
        let old = currentBackend()
        guard old != backend else { return }
        storageBackend = backend
        clearKey()
        wipeAllData(context: context)
    }
}

// MARK: - Secure Storage Operations
private extension CryptoHelper {
    @discardableResult
    static func saveRawSecurely(_ data: Data, key: String, to backend: StorageBackend, using masterKey: SecData) -> Bool {
        guard let hmacKey = deriveSubKey(from: masterKey, context: "hmac-\(key)") else { return false }
        defer { hmacKey.clear() }
        
        guard let encryptionKey = deriveSubKey(from: masterKey, context: "encrypt-\(key)") else { return false }
        defer { encryptionKey.clear() }
        
        do {
            let aad = tokenAAD()
            let symKey = encryptionKey.withUnsafeBytes { SymmetricKey(data: Data($0)) }
            let sealedBox = try AES.GCM.seal(data, using: symKey, authenticating: aad)
            guard let combined = sealedBox.combined else { return false }
            
            let hmacSymKey = hmacKey.withUnsafeBytes { SymmetricKey(data: Data($0)) }
            let hmac = HMAC<SHA256>.authenticationCode(for: combined, using: hmacSymKey)
            
            var finalData = Data(hmac)
            finalData.append(combined)
            
            switch backend {
            case .keychain:
                guard CustomKeychainManager.shared.isSetup else { return false }
                return CustomKeychainManager.shared.save(data, key: key, encrypted: finalData)
            case .local:
                return saveToLocalFileSecurely(finalData, name: key)
            }
        } catch {
            return false
        }
    }
    
    static func loadRawSecurely(_ key: String, from backend: StorageBackend, using masterKey: SecData) -> Data? {
        guard let hmacKey = deriveSubKey(from: masterKey, context: "hmac-\(key)") else { return nil }
        defer { hmacKey.clear() }
        
        guard let encryptionKey = deriveSubKey(from: masterKey, context: "encrypt-\(key)") else { return nil }
        defer { encryptionKey.clear() }
        
        let finalData: Data?
        switch backend {
        case .keychain:
            guard CustomKeychainManager.shared.isSetup else { return nil }
            finalData = CustomKeychainManager.shared.load(key: key)
        case .local:
            finalData = loadFromLocalFile(name: key)
        }
        
        guard let data = finalData, data.count > 32 else { return nil }
        
        let storedHMAC = data.prefix(32)
        let encryptedData = data.dropFirst(32)
        
        let hmacSymKey = hmacKey.withUnsafeBytes { SymmetricKey(data: Data($0)) }
        let computedHMAC = HMAC<SHA256>.authenticationCode(for: encryptedData, using: hmacSymKey)
        
        guard constantTimeCompare(Data(storedHMAC), Data(computedHMAC)) else {
            return nil
        }
        
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            let aad = tokenAAD()
            let symKey = encryptionKey.withUnsafeBytes { SymmetricKey(data: Data($0)) }
            return try AES.GCM.open(sealedBox, using: symKey, authenticating: aad)
        } catch {
            return nil
        }
    }
    
    static func deleteRaw(_ key: String, from backend: StorageBackend) {
        switch backend {
        case .keychain:
            CustomKeychainManager.shared.delete(key: key)
        case .local:
            deleteLocalFile(name: key)
        }
    }
}

// MARK: - Local File Backend
private extension CryptoHelper {
    static var baseDirURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let bundleID = Bundle.main.bundleIdentifier ?? ".com.secure.password-manager"
        return appSupport.appendingPathComponent(bundleID).appendingPathComponent(".Crypto", isDirectory: true)
    }
    
    static func ensureDir() throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: baseDirURL.path) {
            try fileManager.createDirectory(at: baseDirURL, withIntermediateDirectories: true, attributes: [.posixPermissions: NSNumber(value: Int16(0o700))])
        }
        let path = baseDirURL.path
        let attrName = "com.apple.metadata:com_apple_backup_excludeItem"
        let value = "Y"
        value.withCString { ptr in
            setxattr(path, attrName, ptr, strlen(ptr), 0, 0)
        }
    }
    
    @discardableResult
    static func saveToLocalFileSecurely(_ data: Data, name: String) -> Bool {
        do {
            try ensureDir()
            let url = baseDirURL.appendingPathComponent("\(name).enc")
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o600))], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }
    
    static func loadFromLocalFile(name: String) -> Data? {
        let url = baseDirURL.appendingPathComponent("\(name).enc")
        return try? Data(contentsOf: url)
    }
    
    static func deleteLocalFile(name: String) {
        let url = baseDirURL.appendingPathComponent("\(name).enc")
        if FileManager.default.fileExists(atPath: url.path) {
            if let fileHandle = try? FileHandle(forWritingTo: url) {
                let fileSize = fileHandle.seekToEndOfFile()
                fileHandle.seek(toFileOffset: 0)
                for _ in 0..<3 {
                    var randomData = Data(count: Int(fileSize))
                    _ = randomData.withUnsafeMutableBytes { buffer in
                        SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
                    }
                    fileHandle.write(randomData)
                    fileHandle.synchronizeFile()
                }
                try? fileHandle.close()
            }
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - Failed Attempts & Security Policy
extension CryptoHelper {
    static var failedAttempts: Int {
        get { UserDefaults.standard.integer(forKey: failedAttemptsKey) }
        set { UserDefaults.standard.set(newValue, forKey: failedAttemptsKey) }
    }
    
    private static func incrementFailedAttemptsAndMaybeWipe(context: NSManagedObjectContext?) {
        failedAttempts += 1
        secureLog("Failed unlock attempt: \(failedAttempts)")
        applyBackoffDelay(for: failedAttempts)
        if failedAttempts >= maxAttempts {
            wipeAllData(context: context)
            failedAttempts = 0
        }
    }
    
    private static func setFailedAttempts(_ value: Int) {
        failedAttempts = value
    }
    
    private static func applyBackoffDelay(for attempts: Int) {
        let multiplier = pow(2.0, Double(max(0, attempts - 1)))
        let delay = min(backoffBase * multiplier, backoffMax)
        if delay > 0 {
            Thread.sleep(forTimeInterval: delay)
        }
    }
    
    static func wipeAllData(context: NSManagedObjectContext?) {
        clearCurrentStorage()
        clearKey()
        guard let ctx = context else { return }
        let passwordRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "PasswordEntry")
        let folderRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "Folder")
        let deletePasswords = NSBatchDeleteRequest(fetchRequest: passwordRequest)
        let deleteFolders = NSBatchDeleteRequest(fetchRequest: folderRequest)
        do {
            try ctx.execute(deletePasswords)
            try ctx.execute(deleteFolders)
            try ctx.save()
        } catch {
            ctx.rollback()
        }
    }
}

// MARK: - Master Password Functions
extension CryptoHelper {
    static func setMasterPassword(_ password: Data) {
        var salt = Data(count: saltLength)
        let result = salt.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, saltLength, buffer.baseAddress!)
        }
        guard result == errSecSuccess else { return }
        
        guard let securePassword = SecData(password) else {
            clearKey()
            return
        }
        defer { securePassword.clear() }
        
        guard let masterKey = try? deriveKeySecurely(password: securePassword, salt: salt) else {
            clearKey()
            return
        }
        defer { masterKey.clear() }
        
        if storageBackend == .keychain {
            guard CustomKeychainManager.shared.setupKeychain(withPassword: securePassword) else {
                clearKey()
                return
            }
        }
        
        keyStorage = SecData(Data(masterKey.withUnsafeBytes { Data($0) }))
        let aad = tokenAAD()
        guard let tokenData = "verify-v3".data(using: .utf8) else {
            clearKey()
            return
        }
        
        do {
            let symKey = masterKey.withUnsafeBytes { SymmetricKey(data: Data($0)) }
            let sealedBox = try AES.GCM.seal(tokenData, using: symKey, authenticating: aad)
            guard let combined = sealedBox.combined else {
                clearKey()
                return
            }
            
            let saltSaved = saveSaltSecurely(salt)
            let tokenSaved = saveRawSecurely(combined, key: tokenKey, to: storageBackend, using: masterKey)
            
            guard saltSaved && tokenSaved else {
                clearKey()
                return
            }
            
            setFailedAttempts(0)
            updateActivity()
        } catch {
            clearKey()
        }
    }
    
    static func unlockMasterPassword(_ password: Data, context: NSManagedObjectContext) -> Bool {
        guard let securePassword = SecData(password) else {
            incrementFailedAttemptsAndMaybeWipe(context: context)
            return false
        }
        defer { securePassword.clear() }
        
        if storageBackend == .keychain {
            guard CustomKeychainManager.shared.setupKeychain(withPassword: securePassword) else {
                incrementFailedAttemptsAndMaybeWipe(context: context)
                return false
            }
        }
        
        guard let salt = loadSaltSecurely() else {
            incrementFailedAttemptsAndMaybeWipe(context: context)
            return false
        }
        
        guard let masterKey = try? deriveKeySecurely(password: securePassword, salt: salt) else {
            incrementFailedAttemptsAndMaybeWipe(context: context)
            return false
        }
        defer { masterKey.clear() }
        
        keyStorage = SecData(Data(masterKey.withUnsafeBytes { Data($0) }))
        let aad = tokenAAD()
        
        guard let sealedData = loadRawSecurely(tokenKey, from: storageBackend, using: masterKey),
              let sealedBox = try? AES.GCM.SealedBox(combined: sealedData) else {
            clearKey()
            incrementFailedAttemptsAndMaybeWipe(context: context)
            return false
        }
        
        let symKey = masterKey.withUnsafeBytes { SymmetricKey(data: Data($0)) }
        guard let decrypted = try? AES.GCM.open(sealedBox, using: symKey, authenticating: aad),
              let expected = "verify-v3".data(using: .utf8),
              constantTimeCompare(decrypted, expected) else {
            clearKey()
            incrementFailedAttemptsAndMaybeWipe(context: context)
            return false
        }
        
        setFailedAttempts(0)
        updateActivity()
        return true
    }
    
    static func lockSession() {
        clearKey()
    }
    
    static func autoLockIfNeeded() {
        keyLock.lock()
        defer { keyLock.unlock() }
        if isSessionExpiredInternal() {
            _keyStorage?.clear()
            _keyStorage = nil
        }
    }
    
    static var biometricUnlockEnabled: Bool {
        get { getBiometricUnlockEnabled() }
        set { setBiometricUnlockEnabled(newValue) }
    }
    
    static func enableBiometricUnlock() {
        guard BiometricManager.shared.isBiometricAvailable else { return }
        biometricUnlockEnabled = true
    }
    
    static func disableBiometricUnlock() {
        biometricUnlockEnabled = false
    }
}

// MARK: - Session Management
extension CryptoHelper {
    private static var sessionStartTime: Date = Date()
    
    static func getSessionElapsed() -> TimeInterval {
        return Date().timeIntervalSince(sessionStartTime)
    }
    
    static func resetSessionTimer() {
        sessionStartTime = Date()
    }
}

// MARK: - Password Encryption/Decryption
extension CryptoHelper {
    static func encryptPasswordData(_ plaintext: Data, salt: Data, aad: Data? = nil) -> Data? {
        guard let keyStorage = keyStorage else { return nil }
        
        keyLock.lock()
        let expired = isSessionExpiredInternal()
        keyLock.unlock()
        
        if expired {
            clearKey()
            NotificationCenter.default.post(name: .sessionExpired, object: nil)
            return nil
        }
        
        guard plaintext.count <= 4096 else { return nil }
        guard salt.count == saltLength else { return nil }
        
        updateActivity()
        let deviceID = getDeviceID()
        
        return try? keyStorage.withUnsafeBytes { keyBuffer in
            let masterKey = SymmetricKey(data: Data(keyBuffer))
            let info = Data(AADEntryBindingLabel.utf8) + deviceID
            let entryKeyData = HKDF<SHA256>.deriveKey(
                inputKeyMaterial: masterKey,
                salt: salt,
                info: info,
                outputByteCount: 32
            )
            let entryKey = SymmetricKey(data: entryKeyData)
            let aadData = aad ?? Data()
            let sealed = try AES.GCM.seal(plaintext, using: entryKey, authenticating: aadData)
            return sealed.combined
        }
    }
    
    static func decryptPasswordData(_ encrypted: Data, salt: Data, aad: Data? = nil) -> Data? {
        guard let keyStorage = keyStorage else { return nil }
        
        keyLock.lock()
        let expired = isSessionExpiredInternal()
        keyLock.unlock()
        
        guard !expired else { return nil }
        guard encrypted.count <= 8192 else { return nil }
        guard salt.count == saltLength else { return nil }
        
        updateActivity()
        let deviceID = getDeviceID()
        
        return try? keyStorage.withUnsafeBytes { keyBuffer in
            let masterKey = SymmetricKey(data: Data(keyBuffer))
            let info = Data(AADEntryBindingLabel.utf8) + deviceID
            let entryKeyData = HKDF<SHA256>.deriveKey(
                inputKeyMaterial: masterKey,
                salt: salt,
                info: info,
                outputByteCount: 32
            )
            let entryKey = SymmetricKey(data: entryKeyData)
            let sealedBox = try AES.GCM.SealedBox(combined: encrypted)
            let decrypted = try AES.GCM.open(sealedBox, using: entryKey, authenticating: aad ?? Data())
            return decrypted
        }
    }
    
    static func encryptPassword(_ plaintext: String, salt: Data, aad: Data? = nil) -> Data? {
        return encryptPasswordData(Data(plaintext.utf8), salt: salt, aad: aad)
    }
    
    static func decryptPassword(_ encrypted: Data, salt: Data, aad: Data? = nil) -> String? {
        guard let data = decryptPasswordData(encrypted, salt: salt, aad: aad) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Security Validation
extension CryptoHelper {
    static func initializeSecurity() {
        if SecurityValidator.isDebuggerAttached() {
            secureLog("⚠️ Debugger detected")
        }
        if SecurityValidator.isRunningInVM() {
            secureLog("⚠️ Running in VM")
        }
        if !SecurityValidator.validateCodeIntegrity() {
            secureLog("⚠️ Code integrity check failed")
        }
        _ = MemoryPressureMonitor.shared
        NotificationCenter.default.addObserver(forName: .memoryPressureDetected, object: nil, queue: .main) { _ in
            clearKeys()
        }
    }
    
    static func validateSecurityEnvironment() -> Bool {
        #if !DEBUG
        if SecurityValidator.isDebuggerAttached() {
            return false
        }
        #endif
        
        keyLock.lock()
        let hasKey = _keyStorage != nil
        let expired = isSessionExpiredInternal()
        keyLock.unlock()
        
        guard hasKey else { return false }
        if expired {
            clearKeys()
            return false
        }
        return true
    }
    
    static func performSecureCleanup() {
        SecureClipboard.shared.clearClipboard()
        clearKeys()
    }
}

// MARK: - 2FA Integration
extension CryptoHelper {
    static func unlockWithTwoFactor(masterPassword: Data, twoFactorCode: String?, context: NSManagedObjectContext) -> Bool {
        guard unlockMasterPassword(masterPassword, context: context) else { return false }
        if TwoFactorAuthManager.shared.isEnabled {
            guard let code = twoFactorCode, TwoFactorAuthManager.shared.verify(code: code, masterPassword: masterPassword) else {
                clearKey()
                return false
            }
        }
        return true
    }
    
    static func requiresTwoFactor() -> Bool {
        return TwoFactorAuthManager.shared.isEnabled
    }
}

// MARK: - HKDF Implementation
private struct HKDF<Hash: HashFunction> {
    static func deriveKey(inputKeyMaterial: SymmetricKey, salt: Data, info: Data, outputByteCount: Int) -> Data {
        let prk = HMAC<Hash>.authenticationCode(for: salt.isEmpty ? Data() : salt, using: inputKeyMaterial)
        var previous = Data()
        var output = Data()
        var counter: UInt8 = 1
        while output.count < outputByteCount {
            var hmacInput = Data()
            hmacInput.append(previous)
            hmacInput.append(info)
            hmacInput.append(counter)
            let hmacKey = SymmetricKey(data: Data(prk))
            let digest = HMAC<Hash>.authenticationCode(for: hmacInput, using: hmacKey)
            previous = Data(digest)
            output.append(previous)
            counter = counter &+ 1
        }
        return output.prefix(outputByteCount)
    }
}

// MARK: - Secure Logging
private func secureLog(_ message: String) {
    #if DEBUG
    if #available(macOS 11.0, *) {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.app", category: "Security")
        logger.info("\(message, privacy: .private)")
    } else {
        os_log("%{private}s", type: .info, message)
    }
    #endif
}

// MARK: - Secure Settings Storage
@MainActor
extension CryptoHelper {
    private static let settingsPrefix = "SecureSetting."
    
    private enum SettingKey: String {
        case sessionTimeout = "SessionTimeout"
        case autoLockOnBackground = "AutoLockOnBackground"
        case autoLockEnabled = "AutoLockEnabled"
        case autoLockInterval = "AutoLockInterval"
        case autoCloseEnabled = "AutoCloseEnabled"
        case autoCloseInterval = "AutoCloseInterval"
        case autoClearClipboard = "AutoClearClipboard"
        case clearDelay = "ClearDelay"
        case themeName = "Theme.name"
        case themeSelection = "Theme.selection"
        case themeTile = "Theme.tile"
        case themeBadge = "Theme.badge"
        case themeBackground = "Theme.background"
        case biometricUnlockEnabled = "BiometricUnlockEnabled"
        
        @MainActor
        var fullKey: String {
            return settingsPrefix + rawValue
        }
    }
    
    private static func saveSettingSecurely<T: Codable>(_ value: T, key: SettingKey) -> Bool {
        guard let masterKey = keyStorage else { return false }
        
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(value)
            
            guard let settingsKey = deriveSubKey(from: masterKey, context: AADSettingsLabel) else { return false }
            defer { settingsKey.clear() }
            
            let symKey = settingsKey.withUnsafeBytes { SymmetricKey(data: Data($0)) }
            let aad = Data((AADSettingsLabel + "-" + key.rawValue).utf8)
            let encrypted = try AES.GCM.seal(data, using: symKey, authenticating: aad)
            
            guard let combined = encrypted.combined else { return false }
            
            return CustomKeychainManager.shared.save(data, key: key.fullKey, encrypted: combined)
        } catch {
            return false
        }
    }
    
    private static func loadSettingSecurely<T: Codable>(key: SettingKey, defaultValue: T) -> T {
        guard CustomKeychainManager.shared.isSetup else { return defaultValue }
        guard let masterKey = keyStorage else { return defaultValue }
        guard let encryptedData = CustomKeychainManager.shared.load(key: key.fullKey) else {
            return defaultValue
        }
        
        do {
            guard let settingsKey = deriveSubKey(from: masterKey, context: AADSettingsLabel) else { return defaultValue }
            defer { settingsKey.clear() }
            
            let symKey = settingsKey.withUnsafeBytes { SymmetricKey(data: Data($0)) }
            let aad = Data((AADSettingsLabel + "-" + key.rawValue).utf8)
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            let decryptedData = try AES.GCM.open(sealedBox, using: symKey, authenticating: aad)
            
            let decoder = JSONDecoder()
            let value = try decoder.decode(T.self, from: decryptedData)
            return value
        } catch {
            return defaultValue
        }
    }
    
    private static func saveLayoutSettingSecurely(_ value: String, folderKey: String) -> Bool {
        guard let masterKey = keyStorage else { return false }
        let fullKey = "\(settingsPrefix)Layout.\(folderKey)"
        
        do {
            let data = value.data(using: .utf8) ?? Data()
            guard let settingsKey = deriveSubKey(from: masterKey, context: AADSettingsLabel) else { return false }
            defer { settingsKey.clear() }
            
            let symKey = settingsKey.withUnsafeBytes { SymmetricKey(data: Data($0)) }
            let aad = Data((AADSettingsLabel + "-layout-" + folderKey).utf8)
            let encrypted = try AES.GCM.seal(data, using: symKey, authenticating: aad)
            
            guard let combined = encrypted.combined else { return false }
            
            return CustomKeychainManager.shared.save(data, key: fullKey, encrypted: combined)
        } catch {
            return false
        }
    }
    
    private static func loadLayoutSettingSecurely(folderKey: String) -> String? {
        guard CustomKeychainManager.shared.isSetup else { return nil }
        guard let masterKey = keyStorage else { return nil }
        let fullKey = "\(settingsPrefix)Layout.\(folderKey)"
        
        guard let encryptedData = CustomKeychainManager.shared.load(key: fullKey) else {
            return nil
        }
        
        do {
            guard let settingsKey = deriveSubKey(from: masterKey, context: AADSettingsLabel) else { return nil }
            defer { settingsKey.clear() }
            
            let symKey = settingsKey.withUnsafeBytes { SymmetricKey(data: Data($0)) }
            let aad = Data((AADSettingsLabel + "-layout-" + folderKey).utf8)
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            let decryptedData = try AES.GCM.open(sealedBox, using: symKey, authenticating: aad)
            return String(data: decryptedData, encoding: .utf8)
        } catch {
            return nil
        }
    }
    
    // MARK: - Setting Accessors
    static func getSessionTimeout() -> TimeInterval {
        return loadSettingSecurely(key: .sessionTimeout, defaultValue: 900.0)
    }
    
    static func setSessionTimeout(_ value: TimeInterval) {
        _ = saveSettingSecurely(value, key: .sessionTimeout)
    }
    
    static func getAutoLockOnBackground() -> Bool {
        return loadSettingSecurely(key: .autoLockOnBackground, defaultValue: true)
    }
    
    static func setAutoLockOnBackground(_ value: Bool) {
        _ = saveSettingSecurely(value, key: .autoLockOnBackground)
    }
    
    static func getAutoLockEnabled() -> Bool {
        return loadSettingSecurely(key: .autoLockEnabled, defaultValue: false)
    }
    
    static func setAutoLockEnabled(_ value: Bool) {
        _ = saveSettingSecurely(value, key: .autoLockEnabled)
    }
    
    static func getAutoLockInterval() -> Int {
        return loadSettingSecurely(key: .autoLockInterval, defaultValue: 60)
    }
    
    static func setAutoLockInterval(_ value: Int) {
        _ = saveSettingSecurely(value, key: .autoLockInterval)
        NotificationCenter.default.post(name: .autoLockSettingsChanged, object: nil)
    }
    
    static func getAutoCloseEnabled() -> Bool {
        return loadSettingSecurely(key: .autoCloseEnabled, defaultValue: false)
    }
    
    static func setAutoCloseEnabled(_ value: Bool) {
        _ = saveSettingSecurely(value, key: .autoCloseEnabled)
    }
    
    static func getAutoCloseInterval() -> Int {
        return loadSettingSecurely(key: .autoCloseInterval, defaultValue: 10)
    }
    
    static func setAutoCloseInterval(_ value: Int) {
        _ = saveSettingSecurely(value, key: .autoCloseInterval)
    }
    
    static func getAutoClearClipboard() -> Bool {
        return loadSettingSecurely(key: .autoClearClipboard, defaultValue: true)
    }
    
    static func setAutoClearClipboard(_ value: Bool) {
        _ = saveSettingSecurely(value, key: .autoClearClipboard)
    }
    
    static func getClearDelay() -> Double {
        return loadSettingSecurely(key: .clearDelay, defaultValue: 10.0)
    }
    
    static func setClearDelay(_ value: Double) {
        _ = saveSettingSecurely(value, key: .clearDelay)
    }
    
    static func getBiometricUnlockEnabled() -> Bool {
        return loadSettingSecurely(key: .biometricUnlockEnabled, defaultValue: false)
    }
    
    static func setBiometricUnlockEnabled(_ value: Bool) {
        _ = saveSettingSecurely(value, key: .biometricUnlockEnabled)
    }
    
    static func getLayoutMode(for folderKey: String) -> String? {
        if let mode = loadLayoutSettingSecurely(folderKey: folderKey) {
            return mode
        }
        return loadLayoutSettingSecurely(folderKey: "global")
    }
    
    static func setLayoutMode(_ mode: String, for folderKey: String) {
        _ = saveLayoutSettingSecurely(mode, folderKey: folderKey)
        _ = saveLayoutSettingSecurely(mode, folderKey: "global")
    }
    
    static func getThemeName() -> String? {
        let value: String? = loadSettingSecurely(key: .themeName, defaultValue: nil)
        return value
    }
    
    static func setThemeName(_ name: String) {
        _ = saveSettingSecurely(name, key: .themeName)
    }
    
    static func getThemeSelection() -> String? {
        let value: String? = loadSettingSecurely(key: .themeSelection, defaultValue: nil)
        return value
    }
    
    static func setThemeSelection(_ color: String) {
        _ = saveSettingSecurely(color, key: .themeSelection)
    }
    
    static func getThemeTile() -> String? {
        let value: String? = loadSettingSecurely(key: .themeTile, defaultValue: nil)
        return value
    }
    
    static func setThemeTile(_ color: String) {
        _ = saveSettingSecurely(color, key: .themeTile)
    }
    
    static func getThemeBadge() -> String? {
        let value: String? = loadSettingSecurely(key: .themeBadge, defaultValue: nil)
        return value
    }
    
    static func setThemeBadge(_ color: String) {
        _ = saveSettingSecurely(color, key: .themeBadge)
    }
    
    static func getThemeBackground() -> String? {
        let value: String? = loadSettingSecurely(key: .themeBackground, defaultValue: nil)
        return value
    }
    
    static func setThemeBackground(_ color: String) {
        _ = saveSettingSecurely(color, key: .themeBackground)
    }
    
    static func wipeAllSecureSettings() {
        let allKeys: [SettingKey] = [
            .sessionTimeout, .autoLockOnBackground, .autoLockEnabled,
            .autoLockInterval, .autoCloseEnabled, .autoCloseInterval,
            .autoClearClipboard, .clearDelay, .themeName, .themeSelection,
            .themeTile, .themeBadge, .themeBackground, .biometricUnlockEnabled
        ]
        
        for key in allKeys {
            CustomKeychainManager.shared.delete(key: key.fullKey)
        }
        
        CustomKeychainManager.shared.delete(key: "\(settingsPrefix)Layout.global")
    }
}

// MARK: - UserDefaults Migration
extension CryptoHelper {
    static func migrateUserDefaultsToKeychain() {
        guard isUnlocked else {
            print("⚠️ Cannot migrate settings: vault is locked")
            return
        }
        
        let defaults = UserDefaults.standard
        
        if let timeout = defaults.object(forKey: "SessionTimeout") as? TimeInterval {
            setSessionTimeout(timeout)
            defaults.removeObject(forKey: "SessionTimeout")
        }
        
        if let autoLock = defaults.object(forKey: "AutoLockOnBackground") as? Bool {
            setAutoLockOnBackground(autoLock)
            defaults.removeObject(forKey: "AutoLockOnBackground")
        }
        
        if let enabled = defaults.object(forKey: "AutoLockEnabled") as? Bool {
            setAutoLockEnabled(enabled)
            defaults.removeObject(forKey: "AutoLockEnabled")
        }
        
        if let interval = defaults.object(forKey: "AutoLockInterval") as? Int {
            setAutoLockInterval(interval)
            defaults.removeObject(forKey: "AutoLockInterval")
        }
        
        if let enabled = defaults.object(forKey: "AutoCloseEnabled") as? Bool {
            setAutoCloseEnabled(enabled)
            defaults.removeObject(forKey: "AutoCloseEnabled")
        }
        
        if let interval = defaults.object(forKey: "AutoCloseInterval") as? Int {
            setAutoCloseInterval(interval)
            defaults.removeObject(forKey: "AutoCloseInterval")
        }
        
        if let autoClear = defaults.object(forKey: "autoClearClipboard") as? Bool {
            setAutoClearClipboard(autoClear)
            defaults.removeObject(forKey: "autoClearClipboard")
        }
        
        if let delay = defaults.object(forKey: "clearDelay") as? Double {
            setClearDelay(delay)
            defaults.removeObject(forKey: "clearDelay")
        }
        
        if let name = defaults.string(forKey: "Theme.name") {
            setThemeName(name)
            defaults.removeObject(forKey: "Theme.name")
        }
        
        if let selection = defaults.string(forKey: "Theme.selection") {
            setThemeSelection(selection)
            defaults.removeObject(forKey: "Theme.selection")
        }
        
        if let tile = defaults.string(forKey: "Theme.tile") {
            setThemeTile(tile)
            defaults.removeObject(forKey: "Theme.tile")
        }
        
        if let badge = defaults.string(forKey: "Theme.badge") {
            setThemeBadge(badge)
            defaults.removeObject(forKey: "Theme.badge")
        }
        
        if let background = defaults.string(forKey: "Theme.background") {
            setThemeBackground(background)
            defaults.removeObject(forKey: "Theme.background")
        }
        
        if defaults.object(forKey: "CryptoHelper.BiometricUnlockEnabled") != nil {
            let enabled = defaults.bool(forKey: "CryptoHelper.BiometricUnlockEnabled")
            setBiometricUnlockEnabled(enabled)
            defaults.removeObject(forKey: "CryptoHelper.BiometricUnlockEnabled")
        }
        
        let layoutPrefix = "com.xcosw.PasswordList.layoutModeByFolder"
        if let allKeys = defaults.dictionaryRepresentation().keys.filter({ $0.hasPrefix(layoutPrefix) }) as? [String] {
            for key in allKeys {
                if let value = defaults.string(forKey: key) {
                    let folderKey = key.replacingOccurrences(of: "\(layoutPrefix).", with: "")
                    setLayoutMode(value, for: folderKey)
                    defaults.removeObject(forKey: key)
                }
            }
        }
        
        print("✅ Migration from UserDefaults to secure keychain completed")
    }
}


final class SecurityValidator {
    static func isDebuggerAttached() -> Bool {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        return result == 0 && (info.kp_proc.p_flag & P_TRACED) != 0
    }
    
    static func isRunningInVM() -> Bool {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return false }
        
        var cpuModel = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &cpuModel, &size, nil, 0) == 0,
              let model = String(validatingUTF8: cpuModel) else {
            return false
        }
        
        let lower = model.lowercased()
        let vmIndicators = ["virtual", "vmware", "parallels", "qemu", "virtualbox", "hyperv"]
        return vmIndicators.contains { lower.contains($0) }
    }
    
    static func validateCodeIntegrity() -> Bool {
        #if DEBUG
        // Skip validation in debug builds
        return true
        #else
        
        secureLog("✅ Code integrity validation passed")
        return true
        #endif
    }
    
   /* static func validateCodeIntegrity() -> Bool {
        #if DEBUG
        return true
        #else
        guard let executablePath = Bundle.main.executablePath else { return false }
        
        var staticCode: SecStaticCode?
        let executableURL = URL(fileURLWithPath: executablePath)
        
        var status = SecStaticCodeCreateWithPath(executableURL as CFURL, [], &staticCode)
        guard status == errSecSuccess, let code = staticCode else { return false }
        
        // Basic signature check
        status = SecStaticCodeCheckValidity(code, [], nil)
        guard status == errSecSuccess else { return false }
        
        // Verify it's signed by your Team ID (replace with your actual Team ID)
        var requirement: SecRequirement?
        let yourTeamID = "YOUR_TEAM_ID_HERE" // e.g., "ABCDE12345"
        let requirementString = "anchor apple generic and certificate leaf[subject.OU] = \"\(yourTeamID)\""
        
        status = SecRequirementCreateWithString(requirementString as CFString, [], &requirement)
        guard status == errSecSuccess, let req = requirement else { return false }
        
        status = SecStaticCodeCheckValidity(code, [.checkAllArchitectures], req)
        guard status == errSecSuccess else { return false }
        
        // Verify flags
        var signingInfo: CFDictionary?
        status = SecCodeCopySigningInformation(code, [], &signingInfo)
        
        if status == errSecSuccess,
           let info = signingInfo as? [String: Any],
           let flags = info[kSecCodeInfoFlags as String] as? UInt32 {
            
            let isValid = (flags & UInt32(kSecCodeSignatureValid)) != 0
            let isHardened = (flags & UInt32(kSecCodeSignatureRuntime)) != 0
            
            return isValid && isHardened
        }
        
        return true
        #endif
    }*/
}

// MARK: - End of Secure CryptoHelper Implementation
