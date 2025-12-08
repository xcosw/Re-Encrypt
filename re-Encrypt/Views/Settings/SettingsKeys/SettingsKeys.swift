//
//  SettingsKeys.swift
//  re-Encrypt
//
//  Created by xcosw.dev on 3.12.2025.
//

// SettingsKeys.swift
@available(macOS 15.0, *)
enum SettingsKey: String {
    // Security
    case sessionTimeout = "SessionTimeout"
    case autoLockOnBackground = "AutoLockOnBackground"
    case biometricUnlockEnabled = "BiometricUnlockEnabled"
    //case deviceBindingEnabled = "deviceBindingEnabled"

    // Auto-Lock
    case autoLockEnabled = "AutoLockEnabled"
    case autoLockInterval = "AutoLockInterval"
    
    // Auto-Close
    case autoCloseEnabled = "AutoCloseEnabled"
    case autoCloseInterval = "AutoCloseInterval"
    
    // Clipboard
    case clearDelay = "ClearDelay"
    
    // Monitoring
    case screenshotDetectionEnabled = "ScreenshotDetectionEnabled"
    case screenshotNotificationsEnabled = "ScreenshotNotificationsEnabled"
    case memoryPressureMonitoringEnabled = "MemoryPressureMonitoringEnabled"
    case memoryPressureAutoLock = "MemoryPressureAutoLock"
    
    // Theme
    case themeName = "Theme.name"
    case themeSelection = "Theme.selection"
    case themeTile = "Theme.tile"
    case themeBadge = "Theme.badge"
    case themeBackground = "Theme.background"
    
    var fullKey: String {
        return "SecureSetting.\(rawValue)"
    }
}
