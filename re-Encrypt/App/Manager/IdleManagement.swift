//
//  IdleManagement.swift
//  re-Encrypt
//
//  Unified idle monitoring system for both auto-lock and auto-close
//

import Foundation
import AppKit
import SwiftUI

// =============================================================
// MARK: - Unified User Activity Monitor (Singleton)
// =============================================================

@MainActor
final class UserActivityMonitor: ObservableObject {
    static let shared = UserActivityMonitor()
    
    /// Called when any input event occurs
    var onActivity: (() -> Void)?
    
    private var monitors: [Any] = []
    private var isMonitoring = false
    private var lastActivityTime = Date()
    private let debounceInterval: TimeInterval = 0.5
    
    private init() {}
    
    func start() {
        guard !isMonitoring else {
            return
        }
        
        stop()
        
        let mask: NSEvent.EventTypeMask = [
            .keyDown,
            .mouseMoved,
            .leftMouseDown,
            .rightMouseDown,
            .scrollWheel,
            .leftMouseDragged,
            .rightMouseDragged
        ]

        // Global monitor (works when app not focused)
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            self?.handleActivity()
        }) {
            monitors.append(global)
        }
        
        // Local monitor (works when app is focused)
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handleActivity()
            return event
        }) {
            monitors.append(local)
        }
        
        isMonitoring = true
    }
    
    func stop() {
        guard !monitors.isEmpty else { return }
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        isMonitoring = false
    }
    
    private func handleActivity() {
        let now = Date()
        guard now.timeIntervalSince(lastActivityTime) >= debounceInterval else {
            return
        }
        
        lastActivityTime = now
        onActivity?()
    }
    @MainActor
    deinit {
        stop()
    }
}

// =============================================================
// MARK: - Idle Action Type
// =============================================================

enum IdleAction: String {
    case lock = "lock"
    case terminate = "terminate"
    case none = "none"
}

// =============================================================
// MARK: - Unified Idle Controller
// =============================================================


@available(macOS 15.0, *)
@MainActor
final class UnifiedIdleController: ObservableObject {
    static let shared = UnifiedIdleController()
    
    // MARK: Published State
    
    @Published private(set) var lockCountdown: Int?
    @Published private(set) var closeCountdown: Int?
    @Published private(set) var isActive = false
    
    // MARK: Configuration
    
    private struct TimerConfig {
        let lockInterval: Int?      // nil = disabled
        let closeInterval: Int?     // nil = disabled
        let warningFraction: Double = 0.33
        
        var lockWarningDuration: Int {
            guard let interval = lockInterval else { return 0 }
            return max(3, Int(Double(interval) * warningFraction))
        }
        
        var closeWarningDuration: Int {
            guard let interval = closeInterval else { return 0 }
            return max(3, Int(Double(interval) * warningFraction))
        }
        
        var lockSilentDuration: Int {
            guard let interval = lockInterval else { return 0 }
            return interval - lockWarningDuration
        }
        
        var closeSilentDuration: Int {
            guard let interval = closeInterval else { return 0 }
            return interval - closeWarningDuration
        }
    }
    
    // MARK: Internal State
    
    private var timer: Timer?
    private var config: TimerConfig?
    private var elapsedSeconds = 0
    private var lastActivityTime = Date()
    private let activityDebounce: TimeInterval = 0.5
    
    private init() {}
    
    // =============================================================
    // MARK: - Public API
    // =============================================================
    
    /// Start unified idle monitoring
    func start() {
        // Get settings
        let lockEnabled = CryptoHelper.getAutoLockEnabled()
        let lockInterval = lockEnabled ? CryptoHelper.getAutoLockInterval() : nil
        
        let closeEnabled = CryptoHelper.getAutoCloseEnabled()
        let closeInterval = closeEnabled ? (CryptoHelper.getAutoCloseInterval() * 60) : nil
        // Nothing enabled?
        guard lockInterval != nil || closeInterval != nil else {
            stop()
            return
        }
        
        // Validate minimum durations
        if let lock = lockInterval, lock < 30 {
            return
        }
        if let close = closeInterval, close < 60 {
            return
        }
        
        stop()
        
        // Configure
        config = TimerConfig(
            lockInterval: lockInterval,
            closeInterval: closeInterval
        )
        
        elapsedSeconds = 0
        lockCountdown = nil
        closeCountdown = nil
        lastActivityTime = Date()
        isActive = true
        
        // Setup activity monitoring
        UserActivityMonitor.shared.onActivity = { [weak self] in
            Task { @MainActor in
                self?.handleUserActivity()
            }
        }
        UserActivityMonitor.shared.start()
        
        // Start timer
        startTimer()
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
        
        UserActivityMonitor.shared.stop()
        
        lockCountdown = nil
        closeCountdown = nil
        elapsedSeconds = 0
        isActive = false
        config = nil
    }
    
    func reset() {
        guard isActive else { return }
        handleUserActivity()
    }
    
    // =============================================================
    // MARK: - Private Implementation
    // =============================================================
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.current.add(timer!, forMode: .common)
    }
    
    private func handleUserActivity() {
        let now = Date()
        guard now.timeIntervalSince(lastActivityTime) >= activityDebounce else {
            return
        }
        
        lastActivityTime = now
        elapsedSeconds = 0
        lockCountdown = nil
        closeCountdown = nil
    }
    
    private func tick() {
        guard let config = config else { return }
        
        elapsedSeconds += 1
        
        // Check auto-lock
        if let lockInterval = config.lockInterval {
            checkLockTimeout(elapsed: elapsedSeconds, config: config, total: lockInterval)
        }
        
        // Check auto-close
        if let closeInterval = config.closeInterval {
            checkCloseTimeout(elapsed: elapsedSeconds, config: config, total: closeInterval)
        }
    }
    
    private func checkLockTimeout(elapsed: Int, config: TimerConfig, total: Int) {
        let silentDuration = config.lockSilentDuration
        let warningDuration = config.lockWarningDuration
        
        // Silent phase
        if elapsed <= silentDuration {
            if elapsed % 30 == 0 {
            }
            if lockCountdown != nil {
                lockCountdown = nil
            }
            return
        }
        
        // Warning phase
        let warningElapsed = elapsed - silentDuration
        let remaining = warningDuration - warningElapsed
        
        if remaining > 0 {
            if lockCountdown != remaining {
                lockCountdown = remaining
            }
            return
        }
        
        // Timeout reached
        if remaining <= 0 && lockCountdown != 0 {
            lockCountdown = 0
            
            // Trigger lock
            stop()
            NotificationCenter.default.post(name: .autoLockTriggered, object: nil)
        }
    }
    
    private func checkCloseTimeout(elapsed: Int, config: TimerConfig, total: Int) {
        let silentDuration = config.closeSilentDuration
        let warningDuration = config.closeWarningDuration
        
        // Silent phase
        if elapsed <= silentDuration {
            if elapsed % 60 == 0 {
            }
            if closeCountdown != nil {
                closeCountdown = nil
            }
            return
        }
        
        // Warning phase
        let warningElapsed = elapsed - silentDuration
        let remaining = warningDuration - warningElapsed
        
        if remaining > 0 {
            if closeCountdown != remaining {
                closeCountdown = remaining
            }
            return
        }
        
        // Timeout reached
        if remaining <= 0 && closeCountdown != 0 {
            closeCountdown = 0
            
            // Trigger termination
            stop()
            Task {
                await CryptoHelper.performSecureCleanup()
                await MainActor.run {
                    NotificationCenter.default.post(name: .applicationLocked, object: nil)
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
                NSApplication.shared.terminate(nil)
            }
        }
    }
    
    @MainActor
    deinit {
        stop()
    }
}
