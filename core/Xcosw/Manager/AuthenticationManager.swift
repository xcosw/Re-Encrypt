//
//  AuthenticationManager.swift
//  re-Encrypt
//
//  Created by xcosw.dev on 13.12.2025.
//

import Foundation
import CoreData


// MARK: - ========================================
// MARK: - 3. AUTHENTICATION MANAGER (Actor)
// MARK: - ========================================

@available(macOS 15.0, *)
actor AuthenticationManager {
    static let shared = AuthenticationManager()
    
    static let maxAttempts = 3
    private static let failedAttemptsKey = "CryptoHelper.failedAttempts.v3"
    private static let backoffBase: TimeInterval = 3.0 // Increased
    private static let backoffMax: TimeInterval = 120.0 // 2 minutes
    private static let permanentLockoutThreshold = 10 // Total failed attempts before permanent lockout
    
    private var _failedAttempts: Int = 0
    private var _totalFailedAttempts: Int = 0
    private var lastBackoffEnd: Date?
    
    private init() {
        _failedAttempts = UserDefaults.standard.integer(forKey: Self.failedAttemptsKey)
        _totalFailedAttempts = UserDefaults.standard.integer(forKey: "TotalFailedAttempts.v3")
    }
    
    var failedAttempts: Int {
        get { _failedAttempts }
    }
    
    var totalFailedAttempts: Int {
        get { _totalFailedAttempts }
    }
    
    func recordFailedAttempt(context: NSManagedObjectContext?) async -> Bool {
        _failedAttempts += 1
        _totalFailedAttempts += 1
        UserDefaults.standard.set(_failedAttempts, forKey: Self.failedAttemptsKey)
        UserDefaults.standard.set(_totalFailedAttempts, forKey: "TotalFailedAttempts.v3")
        
        await AuditLogger.shared.log(
            "Failed authentication attempt \(_failedAttempts)/\(Self.maxAttempts) (total: \(_totalFailedAttempts))",
            level: .warning
        )
        
        // Check for permanent lockout
        if _totalFailedAttempts >= Self.permanentLockoutThreshold {
            await AuditLogger.shared.log(
                "⚠️ PERMANENT LOCKOUT THRESHOLD REACHED - \(_totalFailedAttempts) total failures",
                level: .critical
            )
            await wipeAllData(context: context)
            return true
        }
        
        applyBackoffDelay(for: _failedAttempts)
        
        if _failedAttempts >= Self.maxAttempts {
            await AuditLogger.shared.log("Max attempts reached - wiping data", level: .critical)
            await wipeAllData(context: context)
            _failedAttempts = 0
            UserDefaults.standard.set(0, forKey: Self.failedAttemptsKey)
            return true
        }
        
        return false
    }
    
    func resetAttempts() {
        _failedAttempts = 0
        UserDefaults.standard.set(0, forKey: Self.failedAttemptsKey)
        lastBackoffEnd = nil
        
        Task {
            await AuditLogger.shared.log("Failed attempts reset after successful auth", level: .info)
        }
    }
    
    func resetTotalAttempts() {
        _totalFailedAttempts = 0
        UserDefaults.standard.set(0, forKey: "TotalFailedAttempts.v3")
    }
    
    func getCurrentAttempts() -> Int {
        return _failedAttempts
    }
    
    func isInBackoff() -> Bool {
        guard let backoffEnd = lastBackoffEnd else { return false }
        return Date() < backoffEnd
    }
    
    func getBackoffTimeRemaining() -> TimeInterval {
        guard let backoffEnd = lastBackoffEnd else { return 0 }
        return max(0, backoffEnd.timeIntervalSinceNow)
    }
    
    private func applyBackoffDelay(for attempts: Int) {
        let multiplier = pow(2.0, Double(max(0, attempts - 1)))
        let delay = min(Self.backoffBase * multiplier, Self.backoffMax)
        if delay > 0 {
            lastBackoffEnd = Date().addingTimeInterval(delay)
            Task {
                await AuditLogger.shared.log("Applying backoff delay: \(Int(delay))s", level: .info)
            }
            Thread.sleep(forTimeInterval: delay)
        }
    }
    
     func wipeAllData(context: NSManagedObjectContext?) async {
        await AuditLogger.shared.log("🗑️ EMERGENCY DATA WIPE INITIATED", level: .critical)
        
        await MainActor.run {
            CryptoHelper.clearCurrentStorage()
            CryptoHelper.wipeAllSecureSettings()
        }
        
        await SecureKeyStorage.shared.clearKey()
        
        guard let ctx = context else { return }
        
        await MainActor.run {
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
}
