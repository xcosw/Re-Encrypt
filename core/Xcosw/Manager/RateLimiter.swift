//
//  RateLimiter.swift
//  re-Encrypt
//
//  Created by xcosw.dev on 13.12.2025.
//

import Foundation

// MARK: - ========================================
// MARK: - 2. RATE LIMITER (Actor)
// MARK: - ========================================

@available(macOS 15.0, *)
actor RateLimiter {
    static let shared = RateLimiter()
    
    private var lastAttempt = Date.distantPast
    private let minInterval: TimeInterval = 1.5 // Increased from 1.0
    private let maxAttemptsPerMinute = 3 // Reduced from 5
    private let maxAttemptsPerHour = 10
    private var attemptTimestamps: [Date] = []
    
    private init() {}
    
    func checkAndRecord() throws {
        let now = Date()
        
        // Remove timestamps older than 1 hour
        attemptTimestamps.removeAll { now.timeIntervalSince($0) > 3600 }
        
        // Check hourly limit
        if attemptTimestamps.count >= maxAttemptsPerHour {
            Task {
                await AuditLogger.shared.log("Hourly rate limit exceeded", level: .warning)
            }
            throw SecurityError.rateLimited
        }
        
        // Remove timestamps older than 1 minute
        let recentAttempts = attemptTimestamps.filter { now.timeIntervalSince($0) <= 60 }
        
        // Check per-minute rate limit
        if recentAttempts.count >= maxAttemptsPerMinute {
            Task {
                await AuditLogger.shared.log("Per-minute rate limit exceeded", level: .warning)
            }
            throw SecurityError.rateLimited
        }
        
        // Check minimum interval
        let elapsed = now.timeIntervalSince(lastAttempt)
        if elapsed < minInterval {
            throw SecurityError.rateLimited
        }
        
        // Record attempt
        lastAttempt = now
        attemptTimestamps.append(now)
    }
    
    func reset() {
        attemptTimestamps.removeAll()
        lastAttempt = Date.distantPast
    }
    
    func getRemainingAttempts() -> Int {
        let now = Date()
        let recentAttempts = attemptTimestamps.filter { now.timeIntervalSince($0) <= 60 }
        return max(0, maxAttemptsPerMinute - recentAttempts.count)
    }
}
