import Foundation
import AppKit
import os.log
internal import Combine

// MARK: - Secure Password Storage
final class SecurePasswordStorage: ObservableObject {
    private var storage: SecData?
    private var lastAccess: Date = Date()
    private let timeout: TimeInterval = 300 // 5 minutes
    private let accessLock = NSLock()
    private var autoClearTimer: Timer?

    init() {
        // Clear on app background (macOS/iOS compatible)
        #if os(macOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearOnBackground),
            name: NSApplication.willResignActiveNotification,
            object: nil
        )
        #endif
    }

    // MARK: - Store password (String)
    func set(_ password: String) {
        accessLock.lock()
        defer { accessLock.unlock() }

        storage?.clear()
        if let data = password.data(using: .utf8) {
            storage = SecData(data)
            lastAccess = Date()
            restartAutoClearTimer()
            secureLog("SecurePasswordStorage: Password set")
        }
    }

    // MARK: - Store password (Data)
    func set(_ data: Data) {
        accessLock.lock()
        defer { accessLock.unlock() }

        storage?.clear()
        storage = SecData(data)
        lastAccess = Date()
        restartAutoClearTimer()
        secureLog("SecurePasswordStorage: Data set")
    }

    // MARK: - Retrieve password data
    func get() -> Data? {
        accessLock.lock()
        defer { accessLock.unlock() }

        guard validateAccess() else { return nil }
        lastAccess = Date()
        return storage?.read()
    }

    // MARK: - Retrieve as String
    func getString() -> String? {
        guard let data = get() else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Safe access with closure
    func withSecureData<T>(_ body: (Data) throws -> T) rethrows -> T? {
        accessLock.lock()
        defer { accessLock.unlock() }

        guard validateAccess(), let data = storage?.read() else { return nil }
        lastAccess = Date()

        defer {
            var mutable = data
            mutable.secureClear()
        }
        return try body(data)
    }

    // MARK: - Check password existence
    var hasPassword: Bool {
        accessLock.lock()
        defer { accessLock.unlock() }
        return storage != nil && Date().timeIntervalSince(lastAccess) < timeout
    }

    // MARK: - Validate access and clear if expired
    private func validateAccess() -> Bool {
        if Date().timeIntervalSince(lastAccess) >= timeout {
            clear()
            secureLog("SecurePasswordStorage: Timeout reached — cleared")
            return false
        }
        restartAutoClearTimer()
        return true
    }

    // MARK: - Auto-clear management
    private func restartAutoClearTimer() {
        autoClearTimer?.invalidate()
        autoClearTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            self?.clear()
            secureLog("SecurePasswordStorage: Auto-cleared after timeout")
        }
    }

    @objc private func clearOnBackground() {
        clear()
        secureLog("SecurePasswordStorage: Cleared on background event")
    }

    // MARK: - Clear memory
    func clear() {
        accessLock.lock()
        defer { accessLock.unlock() }

        storage?.clear()
        storage = nil
        lastAccess = Date()
        autoClearTimer?.invalidate()
        autoClearTimer = nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        clear()
    }
}

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


/* import Foundation
 import AppKit
 import os.log
 internal import Combine

 // MARK: - Secure Password Storage (Enhanced)
 final class SecurePasswordStorage: ObservableObject {
     // MARK: - Published State
     @Published private(set) var hasPassword: Bool = false
     @Published private(set) var isLocked: Bool = false
     @Published private(set) var remainingTime: TimeInterval = 0
     
     // MARK: - Private Properties
     private var storage: SecData?
     private var lastAccess: Date = Date()
     private let timeout: TimeInterval
     private let maxTimeout: TimeInterval = 3600 // 1 hour absolute max
     private let queue = DispatchQueue(label: "secure.password.queue", qos: .userInitiated)
     private var autoClearTimer: Timer?
     private var countdownTimer: Timer?
     private var accessCount: Int = 0
     private let maxAccessCount: Int = 1000
     
     // Rate limiting
     private var recentAccesses: [Date] = []
     private let rateLimitWindow: TimeInterval = 1.0
     private let maxAccessesPerSecond = 50
     
     // MARK: - Configuration
     struct Configuration {
         let timeout: TimeInterval
         let enableAutoClear: Bool
         let maxAccessCount: Int
         let rateLimitEnabled: Bool
         
         static let `default` = Configuration(
             timeout: 300,
             enableAutoClear: true,
             maxAccessCount: 1000,
             rateLimitEnabled: true
         )
         
         static let strict = Configuration(
             timeout: 120,
             enableAutoClear: true,
             maxAccessCount: 500,
             rateLimitEnabled: true
         )
     }
     
     private let config: Configuration

     // MARK: - Initialization
     init(configuration: Configuration = .default) {
         self.config = configuration
         self.timeout = min(configuration.timeout, maxTimeout)
         
         setupNotifications()
         
         if configuration.enableAutoClear {
             startCountdownTimer()
         }
     }
     
     private func setupNotifications() {
         #if os(macOS)
         NotificationCenter.default.addObserver(
             self,
             selector: #selector(clearOnBackground),
             name: NSApplication.willResignActiveNotification,
             object: nil
         )
         NotificationCenter.default.addObserver(
             self,
             selector: #selector(clearOnTermination),
             name: NSApplication.willTerminateNotification,
             object: nil
         )
         NotificationCenter.default.addObserver(
             self,
             selector: #selector(handleMemoryPressure),
             name: .memoryPressureDetected,
             object: nil
         )
         #else
         NotificationCenter.default.addObserver(
             self,
             selector: #selector(clearOnBackground),
             name: UIApplication.willResignActiveNotification,
             object: nil
         )
         NotificationCenter.default.addObserver(
             self,
             selector: #selector(clearOnTermination),
             name: UIApplication.willTerminateNotification,
             object: nil
         )
         #endif
     }

     // MARK: - Store Password (String)
     func set(_ password: String) throws {
         try queue.sync {
             guard !password.isEmpty else {
                 throw SecurePasswordError.emptyPassword
             }
             
             guard password.count <= 1024 else {
                 throw SecurePasswordError.passwordTooLong
             }
             
             storage?.clear()
             
             guard let data = password.data(using: .utf8) else {
                 throw SecurePasswordError.encodingFailed
             }
             
             guard let secData = SecData(data) else {
                 throw SecurePasswordError.storageInitFailed
             }
             
             storage = secData
             lastAccess = Date()
             accessCount = 0
             recentAccesses.removeAll()
             
             DispatchQueue.main.async { [weak self] in
                 self?.hasPassword = true
                 self?.isLocked = false
                 self?.updateRemainingTime()
             }
             
             if config.enableAutoClear {
                 restartAutoClearTimer()
             }
             
             secureLog("SecurePasswordStorage: Password set successfully", level: .info)
         }
     }

     // MARK: - Store Password (Data)
     func set(_ data: Data) throws {
         try queue.sync {
             guard !data.isEmpty else {
                 throw SecurePasswordError.emptyPassword
             }
             
             guard data.count <= 1024 else {
                 throw SecurePasswordError.passwordTooLong
             }
             
             storage?.clear()
             
             guard let secData = SecData(data) else {
                 throw SecurePasswordError.storageInitFailed
             }
             
             storage = secData
             lastAccess = Date()
             accessCount = 0
             recentAccesses.removeAll()
             
             DispatchQueue.main.async { [weak self] in
                 self?.hasPassword = true
                 self?.isLocked = false
                 self?.updateRemainingTime()
             }
             
             if config.enableAutoClear {
                 restartAutoClearTimer()
             }
             
             secureLog("SecurePasswordStorage: Data set successfully", level: .info)
         }
     }

     // MARK: - Retrieve Password Data
     func get() throws -> Data {
         return try queue.sync {
             try validateAccess()
             
             guard let data = try storage?.read() else {
                 throw SecurePasswordError.noPasswordStored
             }
             
             lastAccess = Date()
             updateRemainingTime()
             
             return data
         }
     }

     // MARK: - Retrieve as String
     func getString() throws -> String {
         let data = try get()
         
         guard let string = String(data: data, encoding: .utf8) else {
             throw SecurePasswordError.decodingFailed
         }
         
         return string
     }

     // MARK: - Safe Access with Closure
     func withSecureData<T>(_ body: (Data) throws -> T) throws -> T {
         return try queue.sync {
             try validateAccess()
             
             guard let data = try storage?.read() else {
                 throw SecurePasswordError.noPasswordStored
             }
             
             lastAccess = Date()
             updateRemainingTime()
             
             // Copy data for closure use
             var dataCopy = data
             defer {
                 // Securely wipe the copy
                 dataCopy.secureClear()
             }
             
             return try body(dataCopy)
         }
     }
     
     // MARK: - Safe String Access
     func withSecureString<T>(_ body: (String) throws -> T) throws -> T {
         return try withSecureData { data in
             guard let string = String(data: data, encoding: .utf8) else {
                 throw SecurePasswordError.decodingFailed
             }
             return try body(string)
         }
     }

     // MARK: - Validation
     private func validateAccess() throws {
         guard !isLocked else {
             throw SecurePasswordError.locked
         }
         
         guard storage != nil else {
             throw SecurePasswordError.noPasswordStored
         }
         
         // Check timeout
         let timeSinceLastAccess = Date().timeIntervalSince(lastAccess)
         if timeSinceLastAccess >= timeout {
             clear()
             secureLog("SecurePasswordStorage: Timeout reached — cleared", level: .info)
             throw SecurePasswordError.timeout
         }
         
         // Check access count
         accessCount += 1
         if accessCount > config.maxAccessCount {
             clear()
             secureLog("SecurePasswordStorage: Access limit exceeded — cleared", level: .error)
             throw SecurePasswordError.accessLimitExceeded
         }
         
         // Rate limiting
         if config.rateLimitEnabled {
             let now = Date()
             recentAccesses.removeAll { now.timeIntervalSince($0) > rateLimitWindow }
             
             if recentAccesses.count >= maxAccessesPerSecond {
                 lock()
                 secureLog("SecurePasswordStorage: Rate limit exceeded — locked", level: .error)
                 throw SecurePasswordError.rateLimitExceeded
             }
             
             recentAccesses.append(now)
         }
     }

     // MARK: - Timer Management
     private func restartAutoClearTimer() {
         DispatchQueue.main.async { [weak self] in
             guard let self = self else { return }
             
             self.autoClearTimer?.invalidate()
             self.autoClearTimer = Timer.scheduledTimer(
                 withTimeInterval: self.timeout,
                 repeats: false
             ) { [weak self] _ in
                 self?.clear()
                 secureLog("SecurePasswordStorage: Auto-cleared after timeout", level: .info)
             }
         }
     }
     
     private func startCountdownTimer() {
         DispatchQueue.main.async { [weak self] in
             self?.countdownTimer?.invalidate()
             self?.countdownTimer = Timer.scheduledTimer(
                 withTimeInterval: 1.0,
                 repeats: true
             ) { [weak self] _ in
                 self?.updateRemainingTime()
             }
         }
     }
     
     private func updateRemainingTime() {
         DispatchQueue.main.async { [weak self] in
             guard let self = self, self.storage != nil else {
                 self?.remainingTime = 0
                 return
             }
             
             let elapsed = Date().timeIntervalSince(self.lastAccess)
             self.remainingTime = max(0, self.timeout - elapsed)
             
             if self.remainingTime <= 0 {
                 self.clear()
             }
         }
     }

     // MARK: - Lock/Unlock
     func lock() {
         queue.async { [weak self] in
             guard let self = self else { return }
             
             DispatchQueue.main.async {
                 self.isLocked = true
             }
             
             secureLog("SecurePasswordStorage: Locked", level: .info)
         }
     }
     
     func unlock() throws {
         try queue.sync {
             guard storage != nil else {
                 throw SecurePasswordError.noPasswordStored
             }
             
             DispatchQueue.main.async { [weak self] in
                 self?.isLocked = false
             }
             
             secureLog("SecurePasswordStorage: Unlocked", level: .info)
         }
     }

     // MARK: - Clear Memory
     func clear() {
         queue.async { [weak self] in
             guard let self = self else { return }
             
             self.storage?.clear()
             self.storage = nil
             self.lastAccess = Date()
             self.accessCount = 0
             self.recentAccesses.removeAll()
             
             DispatchQueue.main.async {
                 self.hasPassword = false
                 self.isLocked = false
                 self.remainingTime = 0
                 self.autoClearTimer?.invalidate()
                 self.autoClearTimer = nil
             }
             
             secureLog("SecurePasswordStorage: Cleared", level: .info)
         }
     }
     
     // MARK: - Notification Handlers
     @objc private func clearOnBackground() {
         clear()
         secureLog("SecurePasswordStorage: Cleared on background event", level: .info)
     }
     
     @objc private func clearOnTermination() {
         // Synchronous clear for app termination
         queue.sync {
             storage?.clear()
             storage = nil
         }
         secureLog("SecurePasswordStorage: Cleared on termination", level: .info)
     }
     
     @objc private func handleMemoryPressure(_ notification: Notification) {
         if let level = notification.userInfo?["level"] as? String, level == "critical" {
             clear()
             secureLog("SecurePasswordStorage: Cleared due to critical memory pressure", level: .error)
         }
     }

     // MARK: - Diagnostic Info
     func diagnosticInfo() -> [String: Any] {
         return queue.sync {
             return [
                 "has_password": storage != nil,
                 "is_locked": isLocked,
                 "access_count": accessCount,
                 "time_since_last_access": Date().timeIntervalSince(lastAccess),
                 "remaining_time": remainingTime,
                 "timeout": timeout,
                 "recent_accesses": recentAccesses.count
             ]
         }
     }

     deinit {
         countdownTimer?.invalidate()
         autoClearTimer?.invalidate()
         NotificationCenter.default.removeObserver(self)
         
         // Synchronous final clear
         queue.sync {
             storage?.clear()
             storage = nil
         }
     }
 }

 // MARK: - Errors
 enum SecurePasswordError: LocalizedError {
     case emptyPassword
     case passwordTooLong
     case encodingFailed
     case decodingFailed
     case storageInitFailed
     case noPasswordStored
     case timeout
     case accessLimitExceeded
     case rateLimitExceeded
     case locked
     
     var errorDescription: String? {
         switch self {
         case .emptyPassword:
             return "Password cannot be empty"
         case .passwordTooLong:
             return "Password exceeds maximum length (1024 bytes)"
         case .encodingFailed:
             return "Failed to encode password data"
         case .decodingFailed:
             return "Failed to decode password data"
         case .storageInitFailed:
             return "Failed to initialize secure storage"
         case .noPasswordStored:
             return "No password currently stored"
         case .timeout:
             return "Password access timeout - cleared for security"
         case .accessLimitExceeded:
             return "Access limit exceeded - cleared for security"
         case .rateLimitExceeded:
             return "Rate limit exceeded - locked for security"
         case .locked:
             return "Password storage is locked"
         }
     }
     
     var recoverySuggestion: String? {
         switch self {
         case .locked:
             return "Unlock the storage or wait for automatic unlock"
         case .timeout, .accessLimitExceeded, .rateLimitExceeded:
             return "Set a new password to continue"
         case .noPasswordStored:
             return "Store a password first before attempting to retrieve it"
         default:
             return nil
         }
     }
 }

 // MARK: - Notification Names Extension
 extension Notification.Name {
     static let passwordStorageCleared = Notification.Name("passwordStorageCleared")
     static let passwordStorageLocked = Notification.Name("passwordStorageLocked")
 }

 // MARK: - Secure Logging
 private func secureLog(_ message: String, level: OSLogType = .info) {
     #if DEBUG
     if #available(macOS 11.0, *) {
         let logger = Logger(
             subsystem: Bundle.main.bundleIdentifier ?? "com.app.security",
             category: "PasswordStorage"
         )
         switch level {
         case .debug:
             logger.debug("\(message, privacy: .private)")
         case .info:
             logger.info("\(message, privacy: .private)")
         case .error:
             logger.error("\(message, privacy: .private)")
         case .fault:
             logger.fault("\(message, privacy: .private)")
         default:
             logger.log("\(message, privacy: .private)")
         }
     } else {
         os_log("%{private}s", type: level, message)
     }
     #endif
 }

 // MARK: - Usage Example
 /*
  // Basic usage
  let storage = SecurePasswordStorage()
  
  // Store password
  try storage.set("mySecurePassword123")
  
  // Retrieve password safely
  try storage.withSecureString { password in
      // Use password here - it will be cleared automatically
      performAuthenticationWith(password)
  }
  
  // Check if password exists
  if storage.hasPassword {
      // Password is available
  }
  
  // Lock manually
  storage.lock()
  
  // Clear when done
  storage.clear()
  
  // Strict configuration for high-security scenarios
  let strictStorage = SecurePasswordStorage(configuration: .strict)
  */

 
 */
