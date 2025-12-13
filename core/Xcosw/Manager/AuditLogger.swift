//
//  AuditLogger.swift
//  re-Encrypt
//
//  Created by xcosw.dev on 13.12.2025.
//

import Foundation
import os.log
// MARK: - ========================================
// MARK: - 1. AUDIT LOGGER (Actor)
// MARK: - ========================================

@available(macOS 15.0, *)
actor AuditLogger {
    static let shared = AuditLogger()
    
    private let maxLogEntries = 10000
    private var logEntries: [(date: Date, event: String, level: AuditLevel)] = []
    private let logFile = "security_audit.log"
    
    enum AuditLevel: String {
        case info = "INFO"
        case warning = "WARN"
        case critical = "CRIT"
        case security = "SEC"
    }
    
    private init() {
        // Defer async loading to avoid async in initializer
        Task {
            await self.loadLogs()
        }
    }
    
    func log(_ event: String, level: AuditLevel = .info) {
        let entry = (date: Date(), event: event, level: level)
        logEntries.append(entry)
        
        // Trim if too large
        if logEntries.count > maxLogEntries {
            logEntries.removeFirst(logEntries.count - maxLogEntries)
        }
        
        // Write to persistent storage
        saveLogs()
        
        // Also log to system
        secureLog("[\(level.rawValue)] \(event)", level: level == .critical ? .error : .info)
    }
    
    func getRecentLogs(count: Int = 100) -> [(date: Date, event: String, level: AuditLevel)] {
        return Array(logEntries.suffix(count))
    }
    
    func exportLogs() -> String {
        return logEntries.map { entry in
            let formatter = ISO8601DateFormatter()
            return "[\(formatter.string(from: entry.date))] [\(entry.level.rawValue)] \(entry.event)"
        }.joined(separator: "\n")
    }
    
    private func saveLogs() {
        Task.detached {
            // Access actor-isolated properties safely (self is awaited implicitly in actor context)
            let entries = await self.logEntries.map { LogEntry(date: $0.date, event: $0.event, level: $0.level.rawValue) }
            if let data = try? JSONEncoder().encode(entries) {
                // Assuming saveToLocalFileSecurely is now non-isolated (or async if needed)
                _ = await CryptoHelper.saveToLocalFileSecurely(data, name: self.logFile)
            }
        }
    }
    
    private func loadLogs() async {
        // Assuming loadFromLocalFile is now non-isolated (or await if async)
        if let data = await CryptoHelper.loadFromLocalFile(name: logFile),
           let entries = try? JSONDecoder().decode([LogEntry].self, from: data) {
            logEntries = entries.compactMap { entry in
                guard let level = AuditLevel(rawValue: entry.level) else { return nil }
                return (date: entry.date, event: entry.event, level: level)
            }
        }
    }
    
    struct LogEntry: Codable {
        let date: Date
        let event: String
        let level: String
    }
}

// MARK: - Secure Logging
private func secureLog(_ message: String, level: OSLogType = .info) {
    #if DEBUG
    if #available(macOS 11.0, *) {
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.app", category: "Security")
    switch level {
    case .debug: logger.debug("(message, privacy: .private)")
    case .info: logger.info("(message, privacy: .private)")
    case .error: logger.error("(message, privacy: .private)")
    case .fault: logger.fault("(message, privacy: .private)")
    default: logger.log("(message, privacy: .private)")
    }
    } else {
    os_log("%{private}s", type: level, message)
}
#endif
}
