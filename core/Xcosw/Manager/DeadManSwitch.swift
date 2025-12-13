//
//  DeadManSwitch.swift
//  re-Encrypt
//
//  Created by xcosw.dev on 13.12.2025.
//

import Foundation


// MARK: - ========================================
// MARK: - 4. DEAD MAN'S SWITCH (Actor)
// MARK: - ========================================

@available(macOS 15.0, *)
actor DeadManSwitch {
    static let shared = DeadManSwitch()
    
    private let checkInKey = "LastCheckIn.v3"
    private let maxInactivityDays = 90 // 3 months
    
    private init() {}
    
    func recordCheckIn() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: checkInKey)
        Task {
            await AuditLogger.shared.log("Dead man's switch check-in recorded", level: .info)
        }
    }
    
    func shouldTriggerWipe() -> Bool {
        let lastCheckInTimestamp = UserDefaults.standard.double(forKey: checkInKey)
        guard lastCheckInTimestamp > 0 else {
            // First launch
            recordCheckIn()
            return false
        }

        let lastDate = Date(timeIntervalSince1970: lastCheckInTimestamp)
        let daysSinceCheckIn = Date().timeIntervalSince(lastDate) / 86400
        let shouldWipe = daysSinceCheckIn > Double(maxInactivityDays)
        
        if shouldWipe {
            Task {
                await AuditLogger.shared.log("⚠️ Dead man's switch triggered - \(Int(daysSinceCheckIn)) days inactive", level: .critical)
            }
        }
        
        return shouldWipe
    }
    
    func disable() {
        UserDefaults.standard.removeObject(forKey: checkInKey)
        Task {
            await AuditLogger.shared.log("Dead man's switch disabled", level: .security)
        }
    }
    
    func isActive() -> Bool {
            return UserDefaults.standard.object(forKey: checkInKey) != nil
        }
        
    func getDaysUntilWipe() -> Int? {
        let lastCheckInTimestamp = UserDefaults.standard.double(forKey: checkInKey)
        guard lastCheckInTimestamp > 0 else { return nil }
        
        let lastDate = Date(timeIntervalSince1970: lastCheckInTimestamp)
        let daysSinceCheckIn = Date().timeIntervalSince(lastDate) / 86400
        let daysRemaining = maxInactivityDays - Int(daysSinceCheckIn)
        return max(0, daysRemaining)
    }
    
}
