//
//  IntegrityVerifier.swift
//  re-Encrypt
//
//  Created by xcosw.dev on 13.12.2025.
//

import Foundation
import CryptoKit

// MARK: - ========================================
// MARK: - 3. INTEGRITY VERIFIER (Actor)
// MARK: - ========================================

@available(macOS 15.0, *)
actor IntegrityVerifier {
    static let shared = IntegrityVerifier()
    
    private let integrityHashKey = "IntegrityHash.v3"
    private var lastVerification: Date?
    
    private init() {}
    
    func computeAndStoreIntegrityHash() async {
        let components = await gatherCriticalComponents()
        let hash = SHA256.hash(data: components)
        let hashData = Data(hash)
        
        _ = await CryptoHelper.saveToLocalFileSecurely(hashData, name: integrityHashKey)
        lastVerification = Date()
        
        await AuditLogger.shared.log("Integrity hash computed and stored", level: .info)
    }
    
    func verifyIntegrity() async -> Bool {
        guard let storedHash = await CryptoHelper.loadFromLocalFile(name: integrityHashKey) else {
            await AuditLogger.shared.log("No integrity hash found - first run", level: .info)
            await computeAndStoreIntegrityHash()
            return true
        }
        
        let components = await gatherCriticalComponents()
        let currentHash = Data(SHA256.hash(data: components))
        
        let isValid = storedHash == currentHash
        
        if !isValid {
            await AuditLogger.shared.log("⚠️ INTEGRITY CHECK FAILED - Possible tampering detected!", level: .critical)
        } else {
            await AuditLogger.shared.log("Integrity check passed", level: .info)
        }
        
        lastVerification = Date()
        return isValid
    }
    
    private func gatherCriticalComponents() async -> Data {
        var components = Data()
        
        // Device ID
        await MainActor.run {
            components.append(CryptoHelper.deviceIdentifier())
        }
        
        // App version
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            components.append(Data(version.utf8))
        }
        
        // Build number
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            components.append(Data(build.utf8))
        }
        
        return components
    }
    
    func getLastVerificationStatus() -> Bool {
            return lastVerification != nil
        }
        
    func getLastVerificationDate() -> Date? {
            return lastVerification
    }
}
