//
//  SecureKeyStorage.swift
//  re-Encrypt
//
//  Created by xcosw.dev on 13.12.2025.
//

import Foundation

// MARK: - ========================================
// MARK: - 1. SECURE KEY STORAGE (Actor)
// MARK: - ========================================

@available(macOS 15.0, *)
actor SecureKeyStorage {
    static let shared = SecureKeyStorage()
    
    private var keyStorage: SecData?
    private var lastActivity: Date = Date()
    private var keyVersion: Int = 1
    
    private init() {}
    
    func setKey(_ key: SecData?, version: Int = 1) {
        keyStorage?.clear()
        keyStorage = key
        lastActivity = Date()
        keyVersion = version
        
        if let key = key {
            let keyData = key.withUnsafeBytes { Data($0) }
            Task {
                _ = await MemoryProtector.shared.protectMemory(keyData)
            }
        }
    }
    
    func getKey() -> SecData? {
        return keyStorage
    }
    
    func hasKey() -> Bool {
        return keyStorage != nil
    }
    
    func updateActivity() {
        lastActivity = Date()
    }
    
    func isExpired(timeout: TimeInterval) -> Bool {
        return Date().timeIntervalSince(lastActivity) > timeout
    }
    
    func clearKey() {
        keyStorage?.clear()
        keyStorage = nil
        
        Task {
            await MemoryProtector.shared.cleanup()
        }
    }
    
    func getLastActivity() -> Date {
        return lastActivity
    }
    
    func getKeyVersion() -> Int {
        return keyVersion
    }
}
