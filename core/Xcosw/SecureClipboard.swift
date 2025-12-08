//
//  SecureClipboard.swift
//  Password Manager
//
//  Created by xcosw.dev on 5.12.2025.
//

import AppKit
import Foundation
import CryptoKit
import Security
import os.log

// MARK: - Fully Secure Clipboard
@MainActor
final class SecureClipboard: @unchecked Sendable {
    
    static let shared = SecureClipboard()
    
    // Keychain identifiers
    private let keychainService = Bundle.main.bundleIdentifier ?? "com.re-encrypt.app"
    private let deviceKeyAccount = "secureclipboard.devicekey"
    private let entryKeyPrefix = "secureclipboard.entrykey."
    
    // Pasteboard types
    private let textPasteboardType = NSPasteboard.PasteboardType.string
    private let payloadPasteboardType = NSPasteboard.PasteboardType("com.re-encrypt.app.clipboard.payload")
    private let signaturePasteboardType = NSPasteboard.PasteboardType("com.re-encrypt.app.clipboard.signature")
    private let entryIDPasteboardType = NSPasteboard.PasteboardType("com.re-encrypt.app.clipboard.entryid")
    
    private var clearTimer: Task<Void, Never>?
    
    private init() {
        // Clear clipboard on app background
        NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.clearClipboard()
            }
        }
    }
    
    // MARK: - Copy & Sign with per-entry key
    func copy(text: String, entryID: UUID = UUID(), clearAfter delay: TimeInterval = 10) async {
        guard let shadowBuffer = text.secureData() else { return }
        defer { shadowBuffer.clear() }
        
        guard let deviceKey = await deviceKeyData(),
              let entryKey = await entryKeyData(for: entryID) else { return }
        
        // Create payload: timestamp (UInt64) + text
        let timestamp = UInt64(Date().timeIntervalSince1970)
        var payload = Data(from: timestamp)
        do {
             shadowBuffer.withUnsafeBytes { ptr in
                payload.append(contentsOf: ptr)
            }
        } catch {
            secureLog("SecureClipboard: Failed to read shadow buffer")
            return
        }
        
        // Compute HMAC using combined key
        let combinedKey = entryKey + deviceKey
        let signature = hmacSHA256(data: payload, keyData: combinedKey)
        
        // Paste to NSPasteboard
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: textPasteboardType)
        pb.setData(payload, forType: payloadPasteboardType)
        pb.setData(signature, forType: signaturePasteboardType)
        pb.setString(entryID.uuidString, forType: entryIDPasteboardType)
        
        // Start clear timer
        startClearTimer(after: delay)
    }
    
    // MARK: - Verify signature securely
    func verifySignature(for entryID: UUID, maxAge: TimeInterval = 30) async -> Bool {
        let pb = NSPasteboard.general
        guard
            let payloadData = pb.data(forType: payloadPasteboardType),
            let sigData = pb.data(forType: signaturePasteboardType),
            let entryIDStr = pb.string(forType: entryIDPasteboardType),
            entryID.uuidString == entryIDStr,
            payloadData.count >= 8
        else { return false }
        
        guard let payload = SecData(payloadData) else { return false }
        defer { payload.clear() }
        
        guard let deviceKey = await deviceKeyData(),
              let entryKey = await entryKeyData(for: entryID) else { return false }
        
        let combinedKey = entryKey + deviceKey
        
        let computedSignature: Data
        do {
            computedSignature = payload.withUnsafeBytes { buf in
                hmacSHA256(data: Data(buf), keyData: combinedKey)
            }
        } catch {
            secureLog("SecureClipboard: Failed to access SecData during verification")
            return false
        }
        
        guard computedSignature == sigData else { return false }
        
        // Check timestamp freshness (first 8 bytes)
        let timestamp: UInt64
        do {
            timestamp = payload.withUnsafeBytes { buf in
                buf.prefix(8).withUnsafeBytes { $0.load(as: UInt64.self) }
            }
        }
        
        let age = Date().timeIntervalSince1970 - TimeInterval(timestamp)
        return abs(age) <= maxAge
    }
    
    // MARK: - Clear clipboard
    func clearClipboard() async {
        let pb = NSPasteboard.general
        pb.clearContents()
        clearTimer?.cancel()
        clearTimer = nil
    }
    
    // MARK: - Helpers
    private func hmacSHA256(data: Data, keyData: Data) -> Data {
        let key = SymmetricKey(data: keyData)
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: key)
        return Data(mac)
    }
    
    private func startClearTimer(after delay: TimeInterval) {
        clearTimer?.cancel()
        clearTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await self?.clearClipboard()
        }
    }
    
    // MARK: - Device & Entry Keys
    private func deviceKeyData() async -> Data? {
        if let existing = fetchKeyFromKeychain(account: deviceKeyAccount) { return existing }
        var key = Data(count: 32)
        guard key.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) == errSecSuccess }) else { return nil }
        guard storeKeyInKeychain(key, account: deviceKeyAccount) else { return nil }
        return key
    }
    
    private func entryKeyData(for entryID: UUID) async -> Data? {
        let account = entryKeyPrefix + entryID.uuidString
        if let existing = fetchKeyFromKeychain(account: account) { return existing }
        var key = Data(count: 32)
        guard key.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) == errSecSuccess }) else { return nil }
        guard storeKeyInKeychain(key, account: account) else { return nil }
        return key
    }
    
    private func fetchKeyFromKeychain(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess ? item as? Data : nil
    }
    
    private func storeKeyInKeychain(_ key: Data, account: String) -> Bool {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }
}

// MARK: - Data + UUID helpers
extension Data {
    init<T>(from value: T) {
        var value = value
        self = Swift.withUnsafeBytes(of: &value) { Data($0) }
    }
}

extension UUID {
    var uuidData: Data {
        var copy = self.uuid
        return withUnsafeBytes(of: &copy) { Data($0) }
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
