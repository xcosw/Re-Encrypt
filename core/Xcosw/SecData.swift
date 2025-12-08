import Foundation
import Security
import AppKit
import os.log
import Darwin

private let MADV_DONTDUMP = 16
private let MADV_WIPEONFORK = 18

// MARK: - SecData (Fixed - No Internal Timeout)
final class SecData: @unchecked Sendable {

    private var storage: Data
    private let queue = DispatchQueue(label: "secdata.queue", qos: .userInitiated)
    private var isCleared = false
    private var memoryLocked = false
    private var accessCount: Int = 0
    private let maxAccessCount: Int = 1_000_000  // Very high limit - won't interfere with app logic
    
    // REMOVED: Session timeout - app manages this
    // private var lastAccessTime: Date = Date()
    // private let accessTimeout: TimeInterval = 300

    init?(_ data: Data) {
        guard data.count > 0, data.count <= 1_048_576 else {
            secureLog("SecData: Invalid data size")
            return nil
        }
        self.storage = data
        
        if !applyMemoryProtection() {
            #if !DEBUG
            secureLog("SecData: CRITICAL - Memory protection failed, refusing to store data")
            return nil
            #else
            secureLog("SecData: Warning - Memory protection failed (debug mode, continuing)")
            #endif
        }

        // Clear data on app background
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearOnBackground),
            name: NSApplication.willResignActiveNotification,
            object: nil
        )
    }

    private func applyMemoryProtection() -> Bool {
        var success = true
        storage.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress, buffer.count > 0 else {
                success = false
                return
            }

            if mlock(base, buffer.count) == 0 {
                memoryLocked = true
                secureLog("SecData: Memory locked (\(buffer.count) bytes)")
            } else {
                let error = errno
                secureLog("SecData: Could not lock memory (errno: \(error))")
                success = false
            }

            if madvise(base, buffer.count, Int32(MADV_DONTDUMP)) != 0 {
                secureLog("SecData: Warning - Could not set MADV_DONTDUMP")
            }
            if madvise(base, buffer.count, Int32(MADV_WIPEONFORK)) != 0 {
                secureLog("SecData: Warning - Could not set MADV_WIPEONFORK")
            }
            madvise(base, buffer.count, MADV_FREE)
        }
        return success
    }

    func withUnsafeBytes<T>(_ body: (UnsafeRawBufferPointer) throws -> T) rethrows -> T {
        return try queue.sync {
            guard try validateAccessWithoutClear() else {
                throw SecDataError.alreadyCleared
            }
            return try storage.withUnsafeBytes(body)
        }
    }

    func withUnsafeMutableBytes<T>(_ body: (UnsafeMutableRawBufferPointer) throws -> T) rethrows -> T {
        return try queue.sync {
            guard try validateAccessWithoutClear() else {
                throw SecDataError.alreadyCleared
            }
            return try storage.withUnsafeMutableBytes(body)
        }
    }

    func read() -> Data {
        return queue.sync {
            guard validateAccessNoThrow() else { return Data() }
            return storage
        }
    }

    // FIXED: Removed timeout logic - only check cleared state and access count
    private func validateAccessWithoutClear() throws -> Bool {
        guard !isCleared else {
            throw SecDataError.alreadyCleared
        }
        
        accessCount += 1
        
        // Only fail on excessive access count (very high limit)
        if accessCount > maxAccessCount {
            throw SecDataError.accessLimitExceeded
        }
        
        // REMOVED: Session timeout check - app handles this at CryptoHelper level
        
        return true
    }

    private func validateAccessNoThrow() -> Bool {
        guard !isCleared else { return false }
        accessCount += 1
        
        // Only clear on excessive access
        if accessCount > maxAccessCount {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.clear()
            }
            return false
        }
        
        // REMOVED: Session timeout check
        
        return true
    }

    func clear() {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard !self.isCleared else { return }
            
            self.storage.withUnsafeMutableBytes { buffer in
                guard let base = buffer.baseAddress, buffer.count > 0 else { return }

                if self.memoryLocked {
                    munlock(base, buffer.count)
                    self.memoryLocked = false
                }

                // 4-pass wipe: 00 → FF → random → 00
                _ = memset_s(base, buffer.count, 0x00, buffer.count)
                _ = memset_s(base, buffer.count, 0xFF, buffer.count)

                var randomData = Data(count: buffer.count)
                _ = randomData.withUnsafeMutableBytes { randomBuffer in
                    SecRandomCopyBytes(kSecRandomDefault, buffer.count, randomBuffer.baseAddress!)
                }
                randomData.copyBytes(to: buffer)
                _ = memset_s(base, buffer.count, 0x00, buffer.count)

                randomData.withUnsafeMutableBytes { randomBuffer in
                    if let randomBase = randomBuffer.baseAddress {
                        _ = memset_s(randomBase, randomBuffer.count, 0x00, randomBuffer.count)
                    }
                }
            }
            
            self.storage = Data()
            self.isCleared = true
            self.accessCount = 0
            secureLog("SecData: Memory securely cleared")
        }
    }
    
    // Synchronous clear for deinit - NO QUEUE to prevent deadlock
    private func clearSync() {
        // CRITICAL: Don't use queue.sync in deinit - causes deadlock
        // Just clear directly since deinit is already thread-safe (object is being destroyed)
        guard !isCleared else { return }
        
        storage.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress, buffer.count > 0 else { return }

            if memoryLocked {
                munlock(base, buffer.count)
                memoryLocked = false
            }

            _ = memset_s(base, buffer.count, 0x00, buffer.count)
            _ = memset_s(base, buffer.count, 0xFF, buffer.count)

            var randomData = Data(count: buffer.count)
            _ = randomData.withUnsafeMutableBytes { randomBuffer in
                SecRandomCopyBytes(kSecRandomDefault, buffer.count, randomBuffer.baseAddress!)
            }
            randomData.copyBytes(to: buffer)
            _ = memset_s(base, buffer.count, 0x00, buffer.count)

            randomData.withUnsafeMutableBytes { randomBuffer in
                if let randomBase = randomBuffer.baseAddress {
                    _ = memset_s(randomBase, randomBuffer.count, 0x00, randomBuffer.count)
                }
            }
        }
        
        storage = Data()
        isCleared = true
        accessCount = 0
    }

    @objc private func clearOnBackground() {
        clear()
        secureLog("SecData: Cleared on background event")
    }

    deinit {
        // CRITICAL: clearSync() now bypasses the queue to prevent deadlock
        clearSync()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Errors
enum SecDataError: LocalizedError {
    case alreadyCleared
    case accessLimitExceeded
    case invalidSize
    // REMOVED: case accessTimeout

    var errorDescription: String? {
        switch self {
        case .alreadyCleared: return "Attempted to access cleared secure data"
        case .accessLimitExceeded: return "Access limit exceeded - data cleared"
        case .invalidSize: return "Invalid data size"
        }
    }
}

// MARK: - Extensions (unchanged)
extension Data {
    mutating func secureClear() {
        withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress, buffer.count > 0 else { return }
            memset_s(base, buffer.count, 0x00, buffer.count)
            memset_s(base, buffer.count, 0xFF, buffer.count)
            memset_s(base, buffer.count, 0x00, buffer.count)
        }
        self = Data()
    }

    mutating func resetBytes(in range: Range<Int>) {
        withUnsafeMutableBytes { bytes in
            let ptr = bytes.bindMemory(to: UInt8.self)
            for i in range where i < ptr.count {
                ptr[i] = 0
            }
        }
    }

    mutating func secureWipe() {
        withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            memset_s(baseAddress, buffer.count, 0x00, buffer.count)
            memset_s(baseAddress, buffer.count, 0xFF, buffer.count)
            memset_s(baseAddress, buffer.count, 0x00, buffer.count)
        }
        self = Data()
    }
    
    func secureData() -> SecData? {
        return SecData(self)
    }
}

extension String {
    func secureData() -> SecData? {
        guard let data = data(using: .utf8) else { return nil }
        return SecData(data)
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
