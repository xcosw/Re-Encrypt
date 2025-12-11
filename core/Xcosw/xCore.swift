//
//  xCore.swift
//  re-Encrypt
//
//  Created by xcosw.dev on 10.12.2025.
//

//
//  CryptoHelper.swift
//  re-Encrypt
//

import AppKit
import CryptoKit
import CommonCrypto
import LocalAuthentication
import SystemConfiguration
import os.log

// MARK: - Security Error Types
internal enum SecurityError: Error {
    case cryptographicFailure
    case memoryProtectionFailed
    case invalidInput
    case deviceCompromised
    case sessionExpired
    
    internal var localizedDescription: String {
        switch self {
        case .cryptographicFailure: return "Cryptographic operation failed"
        case .memoryProtectionFailed: return "Memory protection failed"
        case .invalidInput: return "Invalid input provided"
        case .deviceCompromised: return "Device security compromised"
        case .sessionExpired: return "Security session expired"
        }
    }
}

// MARK: - ========================================
// MARK: - 1. AUTHENTICATION MANAGER (Actor)
// MARK: - ========================================

@available(macOS 15.0, *)
actor AuthenticationManager {
    static let shared = AuthenticationManager()
    
    static let maxAttempts = 5
    private static let failedAttemptsKey = "CryptoHelper.failedAttempts.v3"
    private static let backoffBase: TimeInterval = 1.0
    private static let backoffMax: TimeInterval = 30.0
    
    private init() {}
    
    var failedAttempts: Int {
        get { UserDefaults.standard.integer(forKey: Self.failedAttemptsKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.failedAttemptsKey) }
    }
    
    func recordFailedAttempt(context: NSManagedObjectContext?) async -> Bool {
        failedAttempts += 1
        print("❌ Failed attempt \(failedAttempts)/\(Self.maxAttempts)")
        
        applyBackoffDelay(for: failedAttempts)
        
        if failedAttempts >= Self.maxAttempts {
            await wipeAllData(context: context)
            failedAttempts = 0
            return true // Max attempts reached
        }
        
        return false
    }
    
    func resetAttempts() {
        failedAttempts = 0
        print("✅ Failed attempts reset")
    }
    
    func getCurrentAttempts() -> Int {
        return failedAttempts
    }
    
    private func applyBackoffDelay(for attempts: Int) {
        let multiplier = pow(2.0, Double(max(0, attempts - 1)))
        let delay = min(Self.backoffBase * multiplier, Self.backoffMax)
        if delay > 0 {
            Thread.sleep(forTimeInterval: delay)
        }
    }
    
    private func wipeAllData(context: NSManagedObjectContext?) async {
        print("🗑️ Wiping all data after max attempts")
        await MainActor.run {
            CryptoHelper.clearCurrentStorage()
            CryptoHelper.clearKey()
        }
        
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

// MARK: - ========================================
// MARK: - 2. SESSION MANAGER (Actor)
// MARK: - ========================================

@available(macOS 15.0, *)
actor SessionManager {
    static let shared = SessionManager()
    
    private var sessionStartTime: Date?
    private var lastActivity: Date = Date()
    
    private init() {}
    
    func startSession() {
        sessionStartTime = Date()
        lastActivity = Date()
        print("🔐 Session started at \(sessionStartTime!)")
    }
    
    func endSession() {
        sessionStartTime = nil
        print("🔒 Session ended")
    }
    
    func updateActivity() {
        lastActivity = Date()
    }
    
    func getSessionElapsed() -> TimeInterval {
        guard let startTime = sessionStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
    
    func getLastActivity() -> Date {
        return lastActivity
    }
    
    func isExpired() async -> Bool {
        let timeout = await MainActor.run {
            SecurityConfigManager.shared.sessionTimeout
        }
        return Date().timeIntervalSince(lastActivity) > timeout
    }
}

// MARK: - ========================================
// MARK: - 3. CORE CRYPTO HELPER (Main Class)
// MARK: - ========================================

@available(macOS 15.0, *)
@MainActor final class CryptoHelper {
    
    // MARK: - Security Constants
    private static let AADMasterTokenLabel = "master-token-v3-macos"
    private static let AADEntryBindingLabel = "entry-binding-v3-macos"

    private static let pbkdf2Iterations: UInt32 = 600_000
    private static let backoffBase: TimeInterval = 1.0
    private static let backoffMax: TimeInterval = 30.0
    static let maxAttempts = 5
    
    static var sessionTimeout: TimeInterval {
        return SecurityConfigManager.shared.sessionTimeout
    }
    
    private static let tokenKey = "MasterPasswordToken.v3"
    private static let saltKey = "MasterPasswordSalt.v3"
    private static let failedAttemptsKey = "CryptoHelper.failedAttempts.v3"
    
    private static let minPasswordLength = 1
    private static let maxPasswordLength = 1024
    private static let saltLength = 32
    private static let maxEncryptedDataSize = 1_048_576
    private static let minEncryptedDataSize = 16
    
    // MARK: - Thread-Safe Key Storage
    private static let keyLock = NSLock()
    private nonisolated(unsafe) static var _keyStorage: SecData?
    private nonisolated(unsafe) static var _lastActivity: Date = Date()
    
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
        
        Task {
            await SessionManager.shared.updateActivity()
        }
    }
    
    // MARK: - Backend Management
    static var hasMasterPassword: Bool {
        return loadFromLocalFile(name: tokenKey) != nil
    }
    
    static func initializeLocalBackend() {
        print("✅ Using local file storage backend")
        try? ensureDir()
    }
    
    static func clearCurrentStorage() {
        deleteLocalFile(name: tokenKey)
        deleteLocalFile(name: saltKey)
        try? FileManager.default.removeItem(at: baseDirURL)
    }
    
    // MARK: - Master Password Management
    static func verifyMasterPassword(password: Data, context: NSManagedObjectContext?) async -> Bool {
        guard password.count > 0 && password.count <= maxPasswordLength else {
            let _ = await AuthenticationManager.shared.recordFailedAttempt(context: context)
            return false
        }
        
        guard let securePassword = SecData(password) else {
            let _ = await AuthenticationManager.shared.recordFailedAttempt(context: context)
            return false
        }
        defer { securePassword.clear() }
        
        guard let salt = loadSaltSecurely() else {
            let _ = await AuthenticationManager.shared.recordFailedAttempt(context: context)
            return false
        }
        
        guard let derivedKey = try? await deriveKeySecurely(password: securePassword, salt: salt) else {
            let _ = await AuthenticationManager.shared.recordFailedAttempt(context: context)
            return false
        }
        
        defer { derivedKey.clear() }
        
        let aad = tokenAAD()
        guard let tokenData = loadRawSecurely(tokenKey, using: derivedKey) else {
            let _ = await AuthenticationManager.shared.recordFailedAttempt(context: context)
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
            await AuthenticationManager.shared.resetAttempts()
            keyStorage = SecData(Data(derivedKey.withUnsafeBytes { Data($0) }))
            updateActivity()
            secureLog("Master password verified successfully")
        } else {
            let _ = await AuthenticationManager.shared.recordFailedAttempt(context: context)
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
    private static func deriveKeySecurely(password: SecData, salt: Data) async throws -> SecData {
        let passwordBytes: [UInt8] = try password.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else {
                throw SecurityError.cryptographicFailure
            }
            return Array(UnsafeRawBufferPointer(start: base, count: ptr.count))
        }

        let iterations: UInt32
        let memoryKiB: UInt32
        #if DEBUG
            iterations = 1
            memoryKiB = 32_000
        #else
            iterations = 3
            memoryKiB = 128_000
        #endif

        let parallelism = UInt32(min(ProcessInfo.processInfo.activeProcessorCount, 4))
        var saltBytes = [UInt8](salt)

        let symmetricKey = try await xCore.deriveKey(
            password: passwordBytes,
            salt: saltBytes,
            iterations: iterations,
            memoryKiB: memoryKiB,
            parallelism: parallelism,
            length: 32
        )

        let keyData = symmetricKey.withUnsafeBytes { Data($0) }
        guard let secureKey = SecData(keyData) else {
            throw SecurityError.memoryProtectionFailed
        }

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
    
    private static func saveSaltSecurely(_ salt: Data) -> Bool {
        let deviceID = getDeviceID()
        let deviceKey = SymmetricKey(data: deviceID)
        
        do {
            let aad = Data("salt-storage-v3".utf8) + deviceID
            let sealedBox = try AES.GCM.seal(salt, using: deviceKey, authenticating: aad)
            
            guard let encrypted = sealedBox.combined else { return false }
            
            return saveToLocalFileSecurely(encrypted, name: saltKey)
        } catch {
            return false
        }
    }

    private static func loadSaltSecurely() -> Data? {
        let deviceID = getDeviceID()
        let deviceKey = SymmetricKey(data: deviceID)
        
        guard let encrypted = loadFromLocalFile(name: saltKey) else { return nil }
        
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: encrypted)
            let aad = Data("salt-storage-v3".utf8) + deviceID
            return try AES.GCM.open(sealedBox, using: deviceKey, authenticating: aad)
        } catch {
            secureLog("❌ Failed to decrypt salt - possible device mismatch")
            return nil
        }
    }
    
    // MARK: - Device Binding
    static func deviceIdentifier() -> Data {
        return getDeviceID()
    }
    
    private static func getDeviceID() -> Data {
        var components = Data()
        
        let platformExpert = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(platformExpert) }
        
        if platformExpert != 0 {
            if let cfUUID = IORegistryEntryCreateCFProperty(platformExpert, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?.takeUnretainedValue() as? String {
                components.append(Data(cfUUID.utf8))
                components.append(0xFF)
            }
        }
        
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        if size > 0 {
            var buffer = [CChar](repeating: 0, count: size)
            if sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 {
                let trimmed = buffer.prefix { $0 != 0 }
                if let model = String(validating: trimmed, as: UTF8.self) {
                    if !isVirtualMachineCPU(model) {
                        components.append(Data(model.utf8))
                        components.append(0xFF)
                    }
                }
            }
        }
        
        if let mac = getPrimaryMACAddress(), !isVirtualMachineMAC(mac) {
            components.append(Data(mac.utf8))
            components.append(0xFF)
        }
        
        if let serial = getHardwareSerialNumber() {
            components.append(Data(serial.utf8))
            components.append(0xFF)
        }
        
        let username = NSUserName()
        if !username.isEmpty {
            components.append(Data(username.utf8))
            components.append(0xFF)
        }
        
        let installTimeKey = "com.app.install-timestamp"
        if let installTime = UserDefaults.standard.string(forKey: installTimeKey) {
            components.append(Data(installTime.utf8))
            components.append(0xFF)
        } else {
            let timestamp = "\(Date().timeIntervalSince1970)"
            UserDefaults.standard.set(timestamp, forKey: installTimeKey)
            components.append(Data(timestamp.utf8))
            components.append(0xFF)
        }
        
        let deviceSaltKey = "com.app.device-salt"
        if let existing = UserDefaults.standard.string(forKey: deviceSaltKey) {
            components.append(Data(existing.utf8))
            components.append(0xFF)
        } else {
            var randomData = Data(count: 32)
            let result = randomData.withUnsafeMutableBytes {
                SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
            }
            guard result == errSecSuccess else {
                fatalError("Failed to generate secure random device salt")
            }
            let deviceSalt = randomData.base64EncodedString()
            UserDefaults.standard.set(deviceSalt, forKey: deviceSaltKey)
            components.append(Data(deviceSalt.utf8))
            components.append(0xFF)
        }
        
        if components.isEmpty {
            if let fallbackUUID = getStableFallbackUUID() {
                components.append(Data(fallbackUUID.utf8))
                components.append(0xFF)
            } else {
                let fallback = "mac-device-\(getSystemUptime())"
                components.append(Data(fallback.utf8))
                components.append(0xFF)
            }
        }
        
        return Data(SHA256.hash(data: components))
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
}

// MARK: - Secure Storage Operations
@available(macOS 15.0, *)
private extension CryptoHelper {
    @discardableResult
    static func saveRawSecurely(_ data: Data, key: String, using masterKey: SecData) -> Bool {
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
            
            return saveToLocalFileSecurely(finalData, name: key)
        } catch {
            return false
        }
    }
    
    static func loadRawSecurely(_ key: String, using masterKey: SecData) -> Data? {
        guard let hmacKey = deriveSubKey(from: masterKey, context: "hmac-\(key)") else { return nil }
        defer { hmacKey.clear() }
        
        guard let encryptionKey = deriveSubKey(from: masterKey, context: "encrypt-\(key)") else { return nil }
        defer { encryptionKey.clear() }
        
        guard let data = loadFromLocalFile(name: key), data.count > 32 else { return nil }
        
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
    
    static func deleteRaw(_ key: String) {
        deleteLocalFile(name: key)
    }
}

// MARK: - Local File Backend
@available(macOS 15.0, *)
extension CryptoHelper {
    static var baseDirURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let bundleID = Bundle.main.bundleIdentifier ?? ".com.secure.password-manager"
        return appSupport.appendingPathComponent(bundleID).appendingPathComponent(".Crypto", isDirectory: true)
    }
    
    static func ensureDir() throws {
        let fm = FileManager.default
        var url = baseDirURL

        if !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [
                    .posixPermissions: NSNumber(value: Int16(0o700))
                ]
            )
        }

        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
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

// MARK: - Failed Attempts & Security Policy (Using AuthenticationManager)
@available(macOS 15.0, *)
extension CryptoHelper {
    static var failedAttempts: Int {
        get {
            Task {
                await AuthenticationManager.shared.getCurrentAttempts()
            }
            return UserDefaults.standard.integer(forKey: failedAttemptsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: failedAttemptsKey)
        }
    }
    
    static func wipeAllData(context: NSManagedObjectContext?) {
        Task {
            await AuthenticationManager.shared.recordFailedAttempt(context: context)
        }
    }
}

// MARK: - Master Password Functions
@available(macOS 15.0, *)
extension CryptoHelper {
    static func setMasterPassword(_ password: Data) async {
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
        
        guard let masterKey = try? await deriveKeySecurely(password: securePassword, salt: salt) else {
            clearKey()
            return
        }
        defer { masterKey.clear() }
        
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
            let tokenSaved = saveRawSecurely(combined, key: tokenKey, using: masterKey)
            
            guard saltSaved && tokenSaved else {
                clearKey()
                return
            }
            
            await AuthenticationManager.shared.resetAttempts()
            updateActivity()
            await SessionManager.shared.startSession()
        } catch {
            clearKey()
        }
    }
    
    static func unlockMasterPassword(_ password: Data, context: NSManagedObjectContext) async -> Bool {
        guard let securePassword = SecData(password) else {
            let _ = await AuthenticationManager.shared.recordFailedAttempt(context: context)
            return false
        }
        defer { securePassword.clear() }
        
        guard let salt = loadSaltSecurely() else {
            let _ = await AuthenticationManager.shared.recordFailedAttempt(context: context)
            return false
        }
        
        guard let masterKey = try? await deriveKeySecurely(password: securePassword, salt: salt) else {
                    let _ = await AuthenticationManager.shared.recordFailedAttempt(context: context)
                    return false
                }
                defer { masterKey.clear() }
                
                keyStorage = SecData(Data(masterKey.withUnsafeBytes { Data($0) }))
                let aad = tokenAAD()
                
                guard let sealedData = loadRawSecurely(tokenKey, using: masterKey),
                      let sealedBox = try? AES.GCM.SealedBox(combined: sealedData) else {
                    clearKey()
                    let _ = await AuthenticationManager.shared.recordFailedAttempt(context: context)
                    return false
                }
                
                let symKey = masterKey.withUnsafeBytes { SymmetricKey(data: Data($0)) }
                guard let decrypted = try? AES.GCM.open(sealedBox, using: symKey, authenticating: aad),
                      let expected = "verify-v3".data(using: .utf8),
                      constantTimeCompare(decrypted, expected) else {
                    clearKey()
                    let _ = await AuthenticationManager.shared.recordFailedAttempt(context: context)
                    return false
                }
                
                await AuthenticationManager.shared.resetAttempts()
                updateActivity()
                await SessionManager.shared.startSession()
                return true
            }
            
            static func lockSession() {
                clearKey()
                Task {
                    await SessionManager.shared.endSession()
                }
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

        // MARK: - Session Management (Using SessionManager)
        @available(macOS 15.0, *)
        extension CryptoHelper {
            static func startSession() {
                Task {
                    await SessionManager.shared.startSession()
                }
            }
            
            static func endSession() {
                Task {
                    await SessionManager.shared.endSession()
                }
            }
            
            static func getSessionElapsed() -> TimeInterval {
                var elapsed: TimeInterval = 0
                Task {
                    elapsed = await SessionManager.shared.getSessionElapsed()
                }
                return elapsed
            }
            
            static func isSessionExpired() -> Bool {
                var expired = false
                Task {
                    expired = await SessionManager.shared.isExpired()
                }
                return expired
            }
        }

        // MARK: - Password Encryption/Decryption
        @available(macOS 15.0, *)
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
            
            static func encryptPassword(_ plaintext: Data, salt: Data, aad: Data? = nil) -> Data? {
                return encryptPasswordData(Data(plaintext), salt: salt, aad: aad)
            }
            
            static func decryptPasswordSecure(
                _ encrypted: Data,
                salt: Data,
                aad: Data? = nil
            ) -> SecData? {
                guard let plaintext = decryptPasswordData(encrypted, salt: salt, aad: aad) else {
                    return nil
                }
                return SecData(plaintext)
            }
            
            static func encryptPasswordFolde(_ plaintext: String, salt: Data, aad: Data? = nil) -> Data? {
                return encryptPasswordData(Data(plaintext.utf8), salt: salt, aad: aad)
            }
            
            static func decryptPasswordFolder(_ encrypted: Data, salt: Data, aad: Data? = nil) -> String? {
                guard let data = decryptPasswordData(encrypted, salt: salt, aad: aad) else { return nil }
                return String(data: data, encoding: .utf8)
            }
        }

        // MARK: - Security Validation
        @available(macOS 15.0, *)
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
                    Task { @MainActor in
                        clearKeys()
                    }
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
            
            static func performSecureCleanup() async {
                await SecureClipboard.shared.clearClipboard()
                clearKeys()
            }
        }

        // MARK: - 2FA Integration
        @available(macOS 15.0, *)
        extension CryptoHelper {
            static func unlockWithTwoFactor(masterPassword: Data, twoFactorCode: String?, context: NSManagedObjectContext) async -> Bool {
                guard await unlockMasterPassword(masterPassword, context: context) else { return false }
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
        @available(macOS 15.0, *)
        extension CryptoHelper {
            private static let AADSettingsLabel = "settings-v3-macos"
            
            static func saveSetting<T: Codable>(_ value: T, key: SettingsKey) -> Bool {
                guard let masterKey = keyStorage else {
                    print("⚠️ Cannot save setting '\(key.rawValue)': vault locked")
                    return false
                }
                
                do {
                    let data = try JSONEncoder().encode(value)
                    
                    guard let settingsKey = deriveSubKey(from: masterKey, context: AADSettingsLabel) else {
                        return false
                    }
                    defer { settingsKey.clear() }
                    
                    let symKey = settingsKey.withUnsafeBytes { SymmetricKey(data: Data($0)) }
                    let aad = Data("\(AADSettingsLabel)-\(key.rawValue)".utf8)
                    let encrypted = try AES.GCM.seal(data, using: symKey, authenticating: aad)
                    
                    guard let combined = encrypted.combined else { return false }
                    
                    return saveToLocalFileSecurely(combined, name: key.fullKey)
                } catch {
                    print("❌ Error saving setting '\(key.rawValue)': \(error)")
                    return false
                }
            }
            
            private static func loadSetting<T: Codable>(key: SettingsKey, defaultValue: T) -> T {
                guard let masterKey = keyStorage else {
                    return defaultValue
                }
                
                guard let encryptedData = loadFromLocalFile(name: key.fullKey) else {
                    return defaultValue
                }
                
                do {
                    guard let settingsKey = deriveSubKey(from: masterKey, context: AADSettingsLabel) else {
                        return defaultValue
                    }
                    defer { settingsKey.clear() }
                    
                    let symKey = settingsKey.withUnsafeBytes { SymmetricKey(data: Data($0)) }
                    let aad = Data("\(AADSettingsLabel)-\(key.rawValue)".utf8)
                    let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
                    let decryptedData = try AES.GCM.open(sealedBox, using: symKey, authenticating: aad)
                    
                    return try JSONDecoder().decode(T.self, from: decryptedData)
                } catch {
                    return defaultValue
                }
            }
            
            // MARK: - Security Settings
            
            static func getSessionTimeout() -> TimeInterval {
                loadSetting(key: .sessionTimeout, defaultValue: 900.0)
            }
            
            static func setSessionTimeout(_ value: TimeInterval) {
                _ = saveSetting(value, key: .sessionTimeout)
            }
            
            static func getAutoLockOnBackground() -> Bool {
                loadSetting(key: .autoLockOnBackground, defaultValue: true)
            }
            
            static func setAutoLockOnBackground(_ value: Bool) {
                _ = saveSetting(value, key: .autoLockOnBackground)
            }
            
            static func getBiometricUnlockEnabled() -> Bool {
                loadSetting(key: .biometricUnlockEnabled, defaultValue: false)
            }
            
            static func setBiometricUnlockEnabled(_ value: Bool) {
                _ = saveSetting(value, key: .biometricUnlockEnabled)
            }
            
            // MARK: - Auto-Lock Settings
            @MainActor
            static func getAutoLockEnabled() -> Bool {
                loadSetting(key: .autoLockEnabled, defaultValue: false)
            }
            
            static func setAutoLockEnabled(_ value: Bool) {
                _ = saveSetting(value, key: .autoLockEnabled)
            }
            
            @MainActor
            static func getAutoLockInterval() -> Int {
                loadSetting(key: .autoLockInterval, defaultValue: 60)
            }
            
            static func setAutoLockInterval(_ value: Int) {
                _ = saveSetting(value, key: .autoLockInterval)
                NotificationCenter.default.post(name: .autoLockSettingsChanged, object: nil)
            }
            
            // MARK: - Auto-Close Settings
            
            static func getAutoCloseEnabled() -> Bool {
                loadSetting(key: .autoCloseEnabled, defaultValue: false)
            }
            
            static func setAutoCloseEnabled(_ value: Bool) {
                _ = saveSetting(value, key: .autoCloseEnabled)
            }
            
            static func getAutoCloseInterval() -> Int {
                loadSetting(key: .autoCloseInterval, defaultValue: 10)
            }
            
            static func setAutoCloseInterval(_ value: Int) {
                _ = saveSetting(value, key: .autoCloseInterval)
            }
            
            // MARK: - Clipboard Settings
            
            static func getClearDelay() -> Double {
                loadSetting(key: .clearDelay, defaultValue: 10.0)
            }
            
            static func setClearDelay(_ value: Double) {
                _ = saveSetting(value, key: .clearDelay)
            }
            
            // MARK: - Monitoring Settings
            
            static func getScreenshotDetectionEnabled() -> Bool {
                loadSetting(key: .screenshotDetectionEnabled, defaultValue: true)
            }
            
            static func setScreenshotDetectionEnabled(_ value: Bool) {
                _ = saveSetting(value, key: .screenshotDetectionEnabled)
                NotificationCenter.default.post(name: .screenshotSettingsChanged, object: nil)
            }
            
            static func getScreenshotNotificationsEnabled() -> Bool {
                loadSetting(key: .screenshotNotificationsEnabled, defaultValue: true)
            }
            
            static func setScreenshotNotificationsEnabled(_ value: Bool) {
                _ = saveSetting(value, key: .screenshotNotificationsEnabled)
            }
            
            static func getMemoryPressureMonitoringEnabled() -> Bool {
                loadSetting(key: .memoryPressureMonitoringEnabled, defaultValue: true)
            }
            
            static func setMemoryPressureMonitoringEnabled(_ value: Bool) {
                _ = saveSetting(value, key: .memoryPressureMonitoringEnabled)
                NotificationCenter.default.post(name: .memoryPressureSettingsChanged, object: nil)
            }
            
            static func getMemoryPressureAutoLock() -> Bool {
                loadSetting(key: .memoryPressureAutoLock, defaultValue: true)
            }
            
            static func setMemoryPressureAutoLock(_ value: Bool) {
                _ = saveSetting(value, key: .memoryPressureAutoLock)
            }
            
            // MARK: - Theme Settings
            
            static func getThemeName() -> String? {
                loadSetting(key: .themeName, defaultValue: nil as String?)
            }
            
            static func setThemeName(_ name: String) {
                _ = saveSetting(name, key: .themeName)
            }
            
            static func getThemeSelection() -> String? {
                loadSetting(key: .themeSelection, defaultValue: nil as String?)
            }
            
            static func setThemeSelection(_ color: String) {
                _ = saveSetting(color, key: .themeSelection)
            }
            
            static func getThemeTile() -> String? {
                loadSetting(key: .themeTile, defaultValue: nil as String?)
            }
            
            static func setThemeTile(_ color: String) {
                _ = saveSetting(color, key: .themeTile)
            }
            
            static func getThemeBadge() -> String? {
                loadSetting(key: .themeBadge, defaultValue: nil as String?)
            }
            
            static func setThemeBadge(_ color: String) {
                _ = saveSetting(color, key: .themeBadge)
            }
            
            static func getThemeBackground() -> String? {
                loadSetting(key: .themeBackground, defaultValue: nil as String?)
            }
            
            static func setThemeBackground(_ color: String) {
                _ = saveSetting(color, key: .themeBackground)
            }
            
            // MARK: - Wipe All Settings
            
            static func wipeAllSecureSettings() {
                let allKeys: [SettingsKey] = [
                    .sessionTimeout, .autoLockOnBackground, .biometricUnlockEnabled,
                    .autoLockEnabled, .autoLockInterval,
                    .autoCloseEnabled, .autoCloseInterval,
                    .clearDelay,
                    .screenshotDetectionEnabled, .screenshotNotificationsEnabled,
                    .memoryPressureMonitoringEnabled, .memoryPressureAutoLock,
                    .themeName, .themeSelection, .themeTile, .themeBadge, .themeBackground
                ]
                
                for key in allKeys {
                    deleteLocalFile(name: key.fullKey)
                }
                
                print("🗑️ All secure settings wiped")
            }
        }

        // MARK: - SecurityValidator
        @available(macOS 15.0, *)
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
                guard sysctlbyname("machdep.cpu.brand_string", &cpuModel, &size, nil, 0) == 0 else {
                    return false
                }
                
                if let nullIndex = cpuModel.firstIndex(of: 0) {
                    cpuModel = Array(cpuModel[..<nullIndex])
                }
                
                guard let model = String(validating: cpuModel, as: UTF8.self) else {
                    return false
                }
                
                let lower = model.lowercased()
                let vmIndicators = ["virtual", "vmware", "parallels", "qemu", "virtualbox", "hyperv"]
                return vmIndicators.contains { lower.contains($0) }
            }

            static func validateCodeIntegrity() -> Bool {
                #if DEBUG
                return true
                #else
                guard let executablePath = Bundle.main.executablePath else {
                    secureLog("❌ Could not get executable path")
                    return false
                }

                let executableURL = URL(fileURLWithPath: executablePath)
                var staticCode: SecStaticCode?

                var status = SecStaticCodeCreateWithPath(
                    executableURL as CFURL,
                    SecCSFlags(),
                    &staticCode
                )
                guard status == errSecSuccess, let code = staticCode else {
                    secureLog("❌ Failed to create static code reference")
                    return false
                }

                status = SecStaticCodeCheckValidity(code, SecCSFlags(), nil)
                guard status == errSecSuccess else {
                    secureLog("❌ Code signature invalid")
                    return false
                }

                var requirement: SecRequirement?
                let yourTeamID = Bundle.main.object(forInfoDictionaryKey: "TEAM_ID") as? String ?? ""
                let requirementString = "anchor apple generic and certificate leaf[subject.OU] = \"\(yourTeamID)\""

                status = SecRequirementCreateWithString(
                    requirementString as CFString,
                    SecCSFlags(),
                    &requirement
                )
                guard status == errSecSuccess, let req = requirement else {
                    secureLog("❌ Failed to create code requirement")
                    return false
                }
                
                status = SecStaticCodeCheckValidity(
                    code,
                    SecCSFlags(rawValue: kSecCSCheckAllArchitectures),
                    req
                )
                
                if status == errSecSuccess {
                    secureLog("✅ Code integrity validation passed")
                    return true
                } else {
                    secureLog("❌ Code integrity check failed with status: \(status)")
                    return false
                }
                #endif
            }
        }


// MARK: - xCore (RFC 9106 Argon2id-based)
fileprivate enum xCore {
    static func deriveKey(
            password: [UInt8],
            salt: [UInt8],
            iterations t: UInt32 = 3,
            memoryKiB m: UInt32 = 128 * 1024,
            parallelism p: UInt32 = 4,
            length: Int = 32
        ) async throws -> SymmetricKey {

            try await withCheckedThrowingContinuation { cont in
                Task.detached(priority: .userInitiated) {
                    do {
                        // Copy inputs so we can wipe originals
                        var pwd = password
                        var slt = salt

                        let key = try hashRaw(
                            password: &pwd,
                            salt: &slt,
                            t: t,
                            m: m,
                            p: p,
                            length: UInt32(length)
                        )

                        // Wipe inputs securely
                        secureZero(&pwd)
                        secureZero(&slt)

                        cont.resume(returning: SymmetricKey(data: Data(key)))

                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
        }
    
    static func hashRaw(
            password: inout [UInt8],
            salt: inout [UInt8],
            t: UInt32,
            m: UInt32,
            p: UInt32,
            length: UInt32
        ) throws -> [UInt8] {
        // Calculate memory structure
        let lanes = Int(p)
        let blockCount = Int(m)  // Total blocks
        let laneLength = blockCount / lanes  // Blocks per lane
        let segmentLength = laneLength / 4   // Blocks per segment
        
        guard segmentLength > 0 else { throw CryptoError.invalidParameters }
        
        var memory = [Block](repeating: Block(), count: blockCount)
        
        defer {
            for i in memory.indices {
                for j in memory[i].v.indices {
                    memory[i].v[j] = 0
                }
            }
        }

        
        // H0 = Blake2b(p || t || m || taglen || version || password || salt || secret || associated)
        var h0Input = Data()
        h0Input.append(p.littleEndianData)
        h0Input.append(length.littleEndianData)
        h0Input.append(m.littleEndianData)
        h0Input.append(t.littleEndianData)
        h0Input.append(UInt32(0x13).littleEndianData)  // Version 0x13
        h0Input.append(UInt32(2).littleEndianData)      // Type: xCore
        h0Input.append(UInt32(password.count).littleEndianData)
        h0Input.append(contentsOf: password)
        h0Input.append(UInt32(salt.count).littleEndianData)
        h0Input.append(contentsOf: salt)
        h0Input.append(UInt32(0).littleEndianData)  // secret length
        h0Input.append(UInt32(0).littleEndianData)  // associated data length
        
        let h0 = blake2bLong(h0Input, outputLength: 64)
        
        // Initialize first two blocks of each lane
        for lane in 0..<lanes {
            var input0 = h0
            input0.append(UInt32(0).littleEndianData)  // column
            input0.append(UInt32(lane).littleEndianData)
            memory[lane * laneLength] = Block(data: blake2bLong(input0, outputLength: 1024))
            
            var input1 = h0
            input1.append(UInt32(1).littleEndianData)
            input1.append(UInt32(lane).littleEndianData)
            memory[lane * laneLength + 1] = Block(data: blake2bLong(input1, outputLength: 1024))
        }
        
        // Main computation
        for pass in 0..<Int(t) {
            for slice in 0..<4 {
                for lane in 0..<lanes {
                    let startIndex = (pass == 0 && slice == 0) ? 2 : 0
                    
                    for index in startIndex..<segmentLength {
                        let currentIndex = lane * laneLength + slice * segmentLength + index
                        guard currentIndex < blockCount else { continue }
                        
                        let prevIndex = (currentIndex % laneLength == 0) ? (currentIndex + laneLength - 1) : (currentIndex - 1)
                        guard prevIndex < blockCount else { continue }
                        
                        // Calculate reference block index
                        let refIndex = indexingG(
                            pass: pass,
                            lane: lane,
                            slice: slice,
                            index: index,
                            segmentLength: segmentLength,
                            laneLength: laneLength,
                            lanes: lanes,
                            blockCount: blockCount,
                            pseudoRandom: memory[prevIndex].v[0]
                        )
                        
                        guard refIndex < blockCount else { continue }
                        
                        // Compression function G
                        let input = memory[prevIndex] ^ memory[refIndex]
                        memory[currentIndex] = pass == 0 ? compressG(input) : (memory[currentIndex] ^ compressG(input))
                    }
                }
            }
        }
        
        // Final block XOR
        var finalBlock = memory[blockCount - 1]
        for lane in 0..<lanes {
            let lastBlockIndex = (lane + 1) * laneLength - 1
            if lastBlockIndex < blockCount && lastBlockIndex != blockCount - 1 {
                finalBlock = finalBlock ^ memory[lastBlockIndex]
            }
        }
        
        return Array(blake2bLong(finalBlock.data, outputLength: Int(length)))
    }
    
    // MARK: - Secure wipe
@inline(__always)
    private static func secureZero(_ array: inout [UInt8]) {
        array.withUnsafeMutableBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            memset_s(base, ptr.count, 0, ptr.count)
        }
    }
    
    private static func indexingG(
        pass: Int, lane: Int, slice: Int, index: Int,
        segmentLength: Int, laneLength: Int, lanes: Int, blockCount: Int,
        pseudoRandom: UInt64
    ) -> Int {
        let isFirstPass = (pass == 0)
        let isFirstSlice = (slice == 0)
        
        // Reference area size
        var refAreaSize: Int
        if isFirstPass {
            if isFirstSlice {
                refAreaSize = Swift.max(index - 1, 0)
            } else {
                refAreaSize = slice * segmentLength + index - 1
            }
        } else {
            refAreaSize = laneLength - segmentLength + index - 1
        }
        
        guard refAreaSize > 0 else { return lane * laneLength }
        
        // Relative position
        let J1 = UInt32(pseudoRandom & 0xFFFFFFFF)
        let J2 = UInt32((pseudoRandom >> 32) & 0xFFFFFFFF)
        
        let x = (UInt64(J1) * UInt64(J1)) >> 32
        let y = (UInt64(refAreaSize) * x) >> 32
        let relativePos = Swift.max(0, Int(UInt64(refAreaSize) - 1 - y))
        
        // Starting position
        var startPos: Int
        if isFirstPass {
            startPos = lane * laneLength
        } else {
            startPos = lane * laneLength + ((slice + 1) % 4) * segmentLength
        }
        
        // Absolute position - determine reference lane
        let refLane: Int
        if isFirstPass && isFirstSlice {
            refLane = lane
        } else {
            refLane = Int(J2) % lanes
        }
        
        let absolutePos = (refLane * laneLength + startPos + relativePos) % blockCount
        return absolutePos
    }
    
    private static func compressG(_ input: Block) -> Block {
        var R = input
        let Q = input
        
        // Apply column-wise Blake2b round function
        for _ in 0..<8 {
            // Column-wise pass
            for col in 0..<8 {
                var a = R.v[col]
                var b = R.v[col + 16]
                var c = R.v[col + 32]
                var d = R.v[col + 48]
                var e = R.v[col + 64]
                var f = R.v[col + 80]
                var g = R.v[col + 96]
                var h = R.v[col + 112]
                
                gb(&a, &b, &c, &d, &e, &f, &g, &h)
                
                R.v[col] = a
                R.v[col + 16] = b
                R.v[col + 32] = c
                R.v[col + 48] = d
                R.v[col + 64] = e
                R.v[col + 80] = f
                R.v[col + 96] = g
                R.v[col + 112] = h
            }
            
            // Diagonal pass
            for diag in 0..<8 {
                var a = R.v[diag]
                var b = R.v[(diag + 1) % 8 + 16]
                var c = R.v[(diag + 2) % 8 + 32]
                var d = R.v[(diag + 3) % 8 + 48]
                var e = R.v[(diag + 4) % 8 + 64]
                var f = R.v[(diag + 5) % 8 + 80]
                var g = R.v[(diag + 6) % 8 + 96]
                var h = R.v[(diag + 7) % 8 + 112]
                
                gb(&a, &b, &c, &d, &e, &f, &g, &h)
                
                R.v[diag] = a
                R.v[(diag + 1) % 8 + 16] = b
                R.v[(diag + 2) % 8 + 32] = c
                R.v[(diag + 3) % 8 + 48] = d
                R.v[(diag + 4) % 8 + 64] = e
                R.v[(diag + 5) % 8 + 80] = f
                R.v[(diag + 6) % 8 + 96] = g
                R.v[(diag + 7) % 8 + 112] = h
            }
        }
        
        // Row-wise pass
        for row in 0..<16 {
            var locals = [UInt64](repeating: 0, count: 8)
            for j in 0..<8 {
                locals[j] = R.v[row * 8 + j]
            }
            
            var a = locals[0], b = locals[1], c = locals[2], d = locals[3]
            var e = locals[4], f = locals[5], g = locals[6], h = locals[7]
            
            gb(&a, &b, &c, &d, &e, &f, &g, &h)
            
            R.v[row * 8] = a
            R.v[row * 8 + 1] = b
            R.v[row * 8 + 2] = c
            R.v[row * 8 + 3] = d
            R.v[row * 8 + 4] = e
            R.v[row * 8 + 5] = f
            R.v[row * 8 + 6] = g
            R.v[row * 8 + 7] = h
        }
        
        return Q ^ R
    }
    
    private static func gb(_ a: inout UInt64, _ b: inout UInt64, _ c: inout UInt64, _ d: inout UInt64,
                          _ e: inout UInt64, _ f: inout UInt64, _ g: inout UInt64, _ h: inout UInt64) {
        a = a &+ b &+ (2 &* mul32(a, b))
        d ^= a
        d = d.rotateRight(32)
        
        c = c &+ d &+ (2 &* mul32(c, d))
        b ^= c
        b = b.rotateRight(24)
        
        a = a &+ b &+ (2 &* mul32(a, b))
        d ^= a
        d = d.rotateRight(16)
        
        c = c &+ d &+ (2 &* mul32(c, d))
        b ^= c
        b = b.rotateRight(63)
    }
    
    private static func mul32(_ x: UInt64, _ y: UInt64) -> UInt64 {
        let x32 = x & 0xFFFFFFFF
        let y32 = y & 0xFFFFFFFF
        return (x32 * y32) & 0xFFFFFFFF
    }
    
    private static func blake2bLong(_ input: Data, outputLength: Int) -> Data {
        if outputLength <= 64 {
            return Data(Blake2b.hash(input, outputLength: outputLength))
        }
        
        var result = Data()
        let v0 = Data(Blake2b.hash(UInt32(outputLength).littleEndianData + input, outputLength: 64))
        result.append(contentsOf: v0)
        
        var remaining = outputLength - 32
        
        while remaining > 64 {
            let vi = Data(Blake2b.hash(v0, outputLength: 64))
            result.append(contentsOf: vi)
            remaining -= 32
        }
        
        if remaining > 0 {
            let vLast = Data(Blake2b.hash(v0, outputLength: remaining))
            result.append(contentsOf: vLast)
        }
        
        return result.prefix(outputLength)
    }
}

// MARK: - Blake2b Implementation
fileprivate struct Blake2b {
    static func hash(_ data: Data, outputLength: Int = 64) -> [UInt8] {
        precondition(outputLength > 0 && outputLength <= 64)
        
        var h = iv
        h[0] ^= 0x01010000 ^ UInt64(outputLength)
        
        var t: (UInt64, UInt64) = (0, 0)
        
        let chunks = stride(from: 0, to: data.count, by: 128)
        for start in chunks {
            let end = Swift.min(start + 128, data.count)
            let chunk = data[start..<end]
            let isLast = (end == data.count)
            
            t.0 += UInt64(chunk.count)
            if t.0 < UInt64(chunk.count) { t.1 += 1 }
            
            var m = [UInt64](repeating: 0, count: 16)
            for i in 0..<Swift.min(chunk.count / 8, 16) {
                let offset = start + i * 8
                if offset + 8 <= data.count {
                    m[i] = data[offset..<offset+8].loadLittleEndian()
                }
            }
            
            compress(&h, m: m, t: t, f: isLast)
        }
        
        var output = [UInt8]()
        for word in h {
            output.append(contentsOf: word.littleEndianBytes.prefix(Swift.min(8, outputLength - output.count)))
        }
        
        return Array(output.prefix(outputLength))
    }
    
    private static let iv: [UInt64] = [
        0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
        0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179
    ]
    
    private static func compress(_ h: inout [UInt64], m: [UInt64], t: (UInt64, UInt64), f: Bool) {
        var v = h + iv
        v[12] ^= t.0
        v[13] ^= t.1
        if f { v[14] = ~v[14] }
        
        let sigma: [[Int]] = [
            [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
            [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
            [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
            [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
            [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
            [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
            [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
            [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
            [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
            [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0]
        ]
        
        for round in 0..<12 {
            let s = sigma[round % 10]
            
            // Copy values to locals to avoid exclusive access violations
            var v0 = v[0], v1 = v[1], v2 = v[2], v3 = v[3]
            var v4 = v[4], v5 = v[5], v6 = v[6], v7 = v[7]
            var v8 = v[8], v9 = v[9], v10 = v[10], v11 = v[11]
            var v12 = v[12], v13 = v[13], v14 = v[14], v15 = v[15]
            
            // Column rounds
            g(&v0, &v4, &v8, &v12, m[s[0]], m[s[1]])
            g(&v1, &v5, &v9, &v13, m[s[2]], m[s[3]])
            g(&v2, &v6, &v10, &v14, m[s[4]], m[s[5]])
            g(&v3, &v7, &v11, &v15, m[s[6]], m[s[7]])
            
            // Diagonal rounds
            g(&v0, &v5, &v10, &v15, m[s[8]], m[s[9]])
            g(&v1, &v6, &v11, &v12, m[s[10]], m[s[11]])
            g(&v2, &v7, &v8, &v13, m[s[12]], m[s[13]])
            g(&v3, &v4, &v9, &v14, m[s[14]], m[s[15]])
            
            // Write back
            v[0] = v0; v[1] = v1; v[2] = v2; v[3] = v3
            v[4] = v4; v[5] = v5; v[6] = v6; v[7] = v7
            v[8] = v8; v[9] = v9; v[10] = v10; v[11] = v11
            v[12] = v12; v[13] = v13; v[14] = v14; v[15] = v15
        }
        
        for i in 0..<8 {
            h[i] ^= v[i] ^ v[i + 8]
        }
    }
    
    private static func g(_ a: inout UInt64, _ b: inout UInt64, _ c: inout UInt64, _ d: inout UInt64,
                         _ x: UInt64, _ y: UInt64) {
        a = a &+ b &+ x
        d = (d ^ a).rotateRight(32)
        c = c &+ d
        b = (b ^ c).rotateRight(24)
        a = a &+ b &+ y
        d = (d ^ a).rotateRight(16)
        c = c &+ d
        b = (b ^ c).rotateRight(63)
    }
}

// MARK: - Block Structure
struct Block {
    var v: [UInt64]
    
    init() {
        v = [UInt64](repeating: 0, count: 128)
    }
    
    init(data: Data) {
        v = [UInt64](repeating: 0, count: 128)
        let wordCount = Swift.min(data.count / 8, 128)
        for i in 0..<wordCount {
            let offset = i * 8
            if offset + 8 <= data.count {
                v[i] = data[offset..<offset+8].loadLittleEndian()
            }
        }
    }
    
    var data: Data {
        var result = Data(capacity: 1024)
        for word in v {
            result.append(contentsOf: word.littleEndianBytes)
        }
        return result
    }
}

extension Block {
    static func ^ (lhs: Block, rhs: Block) -> Block {
        var result = Block()
        for i in 0..<128 {
            result.v[i] = lhs.v[i] ^ rhs.v[i]
        }
        return result
    }
}

// MARK: - Helper Extensions
extension UInt64 {
    nonisolated func rotateRight(_ n: Int) -> UInt64 {
        (self >> n) | (self << (64 - n))
    }
    
    nonisolated func rotateLeft(_ n: Int) -> UInt64 {
        (self << n) | (self >> (64 - n))
    }
    
    nonisolated var littleEndianBytes: [UInt8] {
        [
            UInt8(self & 0xFF),
            UInt8((self >> 8) & 0xFF),
            UInt8((self >> 16) & 0xFF),
            UInt8((self >> 24) & 0xFF),
            UInt8((self >> 32) & 0xFF),
            UInt8((self >> 40) & 0xFF),
            UInt8((self >> 48) & 0xFF),
            UInt8((self >> 56) & 0xFF)
        ]
    }
}

extension UInt32 {
    nonisolated var littleEndianData: Data {
        withUnsafeBytes(of: self.littleEndian) { Data($0) }
    }
}

extension Data {
    nonisolated func loadLittleEndian() -> UInt64 {
        guard count >= 8 else {
            // Pad with zeros if less than 8 bytes
            var value: UInt64 = 0
            let safeCount = Swift.min(count, 8)
            for i in 0..<safeCount {
                value |= UInt64(self[startIndex + i]) << (i * 8)
            }
            return value
        }
        
        return withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return 0 }
            return baseAddress.loadUnaligned(as: UInt64.self).littleEndian
        }
    }
}

// MARK: - Errors & Helpers
enum CryptoError: Error {
    case corrupted
    case badMagic
    case badVersion
    case authenticationFailed
    case invalidParameters
    case xCoreFailed
}

extension FixedWidthInteger {
    nonisolated var data: Data { withUnsafeBytes(of: self) { Data($0) } }
}

// MARK: - Secure Random
struct Randomness {
    nonisolated static func bytes(_ count: Int) -> Data {
        var b = [UInt8](repeating: 0, count: count)
        let result = SecRandomCopyBytes(kSecRandomDefault, count, &b)
        guard result == errSecSuccess else {
            fatalError("Failed to generate secure random bytes")
        }
        return Data(b)
    }
    
    /// Generate cryptographically secure random bytes
    static func secureBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let result = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard result == errSecSuccess else {
            fatalError("Cryptographic random generation failed")
        }
        
        let data = Data(bytes)
        
        // Lock in memory
        data.withUnsafeBytes { ptr in
            if let baseAddress = ptr.baseAddress {
                mlock(baseAddress, ptr.count)
            }
        }
        
        return data
    }
}

/*
//usage

// Before:
CryptoHelper.failedAttempts += 1

// After:
await AuthenticationManager.shared.recordFailedAttempt(context: ctx)

// Before:
_lastActivity = Date()

// After:
await SessionManager.shared.updateActivity()
*/
