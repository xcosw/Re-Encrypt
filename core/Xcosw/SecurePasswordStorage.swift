import Foundation
import AppKit
import os.log

// MARK: - Secure Password Storage
@MainActor
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
    @MainActor
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
    @MainActor
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
    @MainActor
    func get() -> Data? {
        accessLock.lock()
        defer { accessLock.unlock() }

        guard validateAccess() else { return nil }
        lastAccess = Date()
        return storage?.read()
    }

    // MARK: - Retrieve as String
    @MainActor
    func getString() -> String? {
        guard let data = get() else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Safe access with closure
    @MainActor
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
    @MainActor
    var hasPassword: Bool {
        accessLock.lock()
        defer { accessLock.unlock() }
        return storage != nil && Date().timeIntervalSince(lastAccess) < timeout
    }

    // MARK: - Validate access and clear if expired
    @MainActor
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
            Task { @MainActor in self?.clear() }
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
    
    @MainActor
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
