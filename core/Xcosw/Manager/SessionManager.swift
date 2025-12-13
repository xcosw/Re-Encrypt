//
//  SessionManager.swift
//  re-Encrypt
//
//  Created by xcosw.dev on 13.12.2025.
//

import Foundation

// MARK: - ========================================
// MARK: - 4. SESSION MANAGER (Actor)
// MARK: - ========================================

@available(macOS 15.0, *)
actor SessionManager {
    static let shared = SessionManager()
    
    private var sessionStartTime: Date?
    
    private init() {}
    
    func startSession() async {
        sessionStartTime = Date()
        await SecureKeyStorage.shared.updateActivity()
        print("🔐 Session started at \(sessionStartTime!)")
    }
    
    func endSession() {
        sessionStartTime = nil
        print("🔒 Session ended")
    }
    
    func getSessionElapsed() -> TimeInterval {
        guard let startTime = sessionStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
    
    func isExpired() async -> Bool {
        let timeout = await MainActor.run {
            SecurityConfigManager.shared.sessionTimeout
        }
        return await SecureKeyStorage.shared.isExpired(timeout: timeout)
    }
    
    func checkAndThrowIfExpired() async throws {
        if await isExpired() {
            throw SecurityError.sessionExpired
        }
    }
}
