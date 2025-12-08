//
//  SecurityStateManager.swift
//  re-Encrypt
//
//  Created by xcosw.dev on 3.12.2025.
//

import Foundation

// ==========================================
// 4. SECURITY STATE MANAGER
// ==========================================

@available(macOS 15.0, *)
@MainActor
final class SecurityStateManager: ObservableObject {
    static let shared = SecurityStateManager()
    
    @Published private(set) var isUnderMemoryPressure = false
    @Published private(set) var hasActiveSession = false
    @Published private(set) var sessionRemainingTime: TimeInterval = 0
    
    private var sessionTimer: Timer?
    
    private init() {
        setupNotificationObservers()
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryPressure),
            name: .memoryPressureDetected,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionExpired),
            name: .sessionExpired,
            object: nil
        )
    }
    
    func startSession() {
        hasActiveSession = true
        updateSessionTimer()
    }
    
    func endSession() {
        hasActiveSession = false
        sessionTimer?.invalidate()
        sessionTimer = nil
        sessionRemainingTime = 0
    }
    
    private func updateSessionTimer() {
        sessionTimer?.invalidate()
        
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }

                let timeout = CryptoHelper.sessionTimeout
                let elapsed = CryptoHelper.getSessionElapsed()   // now allowed on MainActor
                self.sessionRemainingTime = max(0, timeout - elapsed)

                if self.sessionRemainingTime <= 0 {
                    self.handleSessionExpired()
                }
            }
        }
    }

    
    @objc private func handleMemoryPressure() {
        isUnderMemoryPressure = true
        endSession()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.isUnderMemoryPressure = false
        }
    }
    @MainActor
    @objc private func handleSessionExpired() {
        endSession()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
