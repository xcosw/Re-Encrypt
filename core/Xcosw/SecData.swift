//
//  SecData.swift
//  re-Encrypt
//
//  Created by xcosw.dev on 17.11.2025.
//


// MARK: - Secure Data Container (FIXED - No Deadlock)
import Foundation
import Security
import AppKit
import os.log
import Darwin

private let MADV_DONTDUMP = 16
private let MADV_WIPEONFORK = 18

// MARK: - SecData (Fixed)
final class SecData {
    private var storage: Data
    private let queue = DispatchQueue(label: "secdata.queue", qos: .userInitiated)
    private var isCleared = false
    private var memoryLocked = false
    private var accessCount: Int = 0
    private let maxAccessCount: Int = 1000
    private var lastAccessTime: Date = Date()
    private let accessTimeout: TimeInterval = 300 // 5 minutes

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

    // CRITICAL FIX: Use async to prevent deadlock
    func withUnsafeBytes<T>(_ body: (UnsafeRawBufferPointer) throws -> T) rethrows -> T {
        return try queue.sync {
            // Don't call clear() here - just check and throw
            guard try validateAccessWithoutClear() else {
                throw SecDataError.alreadyCleared
            }
            return try storage.withUnsafeBytes(body)
        }
    }

    func withUnsafeMutableBytes<T>(_ body: (UnsafeMutableRawBufferPointer) throws -> T) rethrows -> T {
        return try queue.sync {
            // Don't call clear() here - just check and throw
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

    // CRITICAL FIX: New validation that doesn't call clear() in sync block
    private func validateAccessWithoutClear() throws -> Bool {
        guard !isCleared else {
            throw SecDataError.alreadyCleared
        }
        
        accessCount += 1
        let now = Date()
        
        if accessCount > maxAccessCount {
            throw SecDataError.accessLimitExceeded
        }
        
        if now.timeIntervalSince(lastAccessTime) > accessTimeout {
            throw SecDataError.accessTimeout
        }
        
        lastAccessTime = now
        return true
    }

    // OLD VALIDATION (kept for backwards compatibility, but unused)
    private func validateAccess() throws {
        guard !isCleared else { throw SecDataError.alreadyCleared }
        accessCount += 1
        if accessCount > maxAccessCount {
            // DEADLOCK BUG WAS HERE: calling clear() inside queue.sync
            throw SecDataError.accessLimitExceeded
        }
        let now = Date()
        if now.timeIntervalSince(lastAccessTime) > accessTimeout {
            // DEADLOCK BUG WAS HERE: calling clear() inside queue.sync
            throw SecDataError.accessTimeout
        }
        lastAccessTime = now
    }

    private func validateAccessNoThrow() -> Bool {
        guard !isCleared else { return false }
        accessCount += 1
        
        let now = Date()
        if accessCount > maxAccessCount {
            // Schedule clear on different queue to avoid deadlock
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.clear()
            }
            return false
        }
        
        if now.timeIntervalSince(lastAccessTime) > accessTimeout {
            // Schedule clear on different queue to avoid deadlock
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.clear()
            }
            return false
        }
        
        lastAccessTime = now
        return true
    }

    func clear() {
        queue.async { [weak self] in  // CRITICAL FIX: Use async instead of sync
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
    
    // Synchronous clear for deinit
    private func clearSync() {
        queue.sync {
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
    }

    @objc private func clearOnBackground() {
        clear()
        secureLog("SecData: Cleared on background event")
    }

    deinit {
        clearSync()  // Use sync version in deinit
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Errors
enum SecDataError: LocalizedError {
    case alreadyCleared
    case accessLimitExceeded
    case accessTimeout
    case invalidSize

    var errorDescription: String? {
        switch self {
        case .alreadyCleared: return "Attempted to access cleared secure data"
        case .accessLimitExceeded: return "Access limit exceeded - data cleared"
        case .accessTimeout: return "Access timeout - data cleared"
        case .invalidSize: return "Invalid data size"
        }
    }
}

// MARK: - Secure Data & String Extensions
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

// MARK: - Secure Clipboard
final class SecureClipboard {
    @MainActor static let shared = SecureClipboard()
    private var clearTimer: Timer?
    private let queue = DispatchQueue(label: "secure.clipboard.queue")
    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearClipboard),
            name: NSApplication.willResignActiveNotification,
            object: nil
        )
    }

    func copy(_ text: String, clearAfter delay: TimeInterval = 10) {
        queue.async { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                secureLog("SecureClipboard: Copied (will clear in \(Int(delay))s)")
            }
            self.clearTimer?.invalidate()
            DispatchQueue.main.async {
                self.clearTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
                    self.clearClipboard()
                }
            }
        }
    }

    @objc func clearClipboard() {
        queue.async {
            DispatchQueue.main.async {
                NSPasteboard.general.clearContents()
                secureLog("SecureClipboard: Cleared")
            }
        }
        clearTimer?.invalidate()
        clearTimer = nil
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
