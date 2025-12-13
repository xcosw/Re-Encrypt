//
//  AntiDebugMonitor.swift
//  re-Encrypt
//
//  Created by xcosw.dev on 13.12.2025.
//

import Foundation

// MARK: - ========================================
// MARK: - 6. ANTI-DEBUG MONITOR (Actor)
// MARK: - ========================================

@available(macOS 15.0, *)
actor AntiDebugMonitor {
    static let shared = AntiDebugMonitor()
    
    private var monitoring = false
    private var checkTask: Task<Void, Never>?
    
    private init() {}
    
    func startMonitoring() {
        guard !monitoring else { return }
        monitoring = true
        
        checkTask = Task {
            while !Task.isCancelled {
                if SecurityValidator.isDebuggerAttached() {
                    await AuditLogger.shared.log("⚠️ DEBUGGER DETECTED - Emergency shutdown", level: .critical)
                    await emergencyShutdown()
                    break
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }
    
    func stopMonitoring() {
        checkTask?.cancel()
        monitoring = false
    }
    
    func isMonitoring() -> Bool {
        monitoring
    }
    
    private func emergencyShutdown() async {
        await CryptoHelper.clearKeys()   // <-- async call is fine

        NotificationCenter.default.post(name: .emergencyShutdown, object: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            exit(0)
        }
    }

}
