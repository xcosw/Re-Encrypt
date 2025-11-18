import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(SwiftUI)
import SwiftUI
#endif

/// Helper for initializing app secure settings
@MainActor
public struct AppInitializationHelper {

    // MARK: - Initialization on App Launch

    /// Call this in `application(_:didFinishLaunchingWithOptions:)` or SwiftUI `App` init
    public static func initialize() {
        print("🚀 Initializing app...")

        // 1. Initialize keychain backend first
        CryptoHelper.initializeKeychainBackend()

        // 2. Don't load secure settings yet (keychain locked on first launch)
        print("✅ App initialization complete (settings will load after unlock)")
    }

    // MARK: - Settings Initialization (After Unlock)

    /// Call after device unlock / biometric unlock
    public static func initializeSecureSettings() {
        print("🔐 Loading secure settings after unlock...")

        if needsMigration() {
            print("📦 Migrating settings to secure storage...")
            CryptoHelper.migrateUserDefaultsToKeychain()
            markMigrationComplete()
        }

        SecurityConfigManager.shared.reload()

        print("✅ Secure settings loaded")
    }

    // MARK: - Default Settings (On First Setup)

    /// Call only at first install
    public static func setDefaultSettings() {
        print("⚙️ Setting default settings...")

        let currentSessionTimeout = CryptoHelper.getSessionTimeout()
        if currentSessionTimeout == 900.0 {
            CryptoHelper.setSessionTimeout(900.0)
        }

        if !hasCustomTransparency() {
            UserDefaults.standard.set(false, forKey: "Settings.transparencyEnabled")
            print("   ✅ Set default TransparencyEnabled: false")
        }

        if !hasCustomAutoLockEnabled() {
            CryptoHelper.setAutoLockEnabled(false)
        }

        if !hasCustomAutoLockInterval() {
            CryptoHelper.setAutoLockInterval(60)
        }

        if !hasCustomAutoCloseEnabled() {
            CryptoHelper.setAutoCloseEnabled(false)
        }

        if !hasCustomAutoCloseInterval() {
            CryptoHelper.setAutoCloseInterval(10)
        }

        if !hasCustomAutoLockOnBackground() {
            CryptoHelper.setAutoLockOnBackground(true)
        }

        if !hasCustomAutoClearClipboard() {
            CryptoHelper.setAutoClearClipboard(true)
        }

        if !hasCustomClearDelay() {
            CryptoHelper.setClearDelay(10.0)
        }

        if !hasCustomBiometricUnlock() {
            CryptoHelper.setBiometricUnlockEnabled(false)
        }

        print("✅ Default settings initialized")
    }

    // MARK: - Migration

    private static let migrationKey = "com.app.settings.migrated.v2"

    private static func needsMigration() -> Bool {
        if UserDefaults.standard.bool(forKey: migrationKey) {
            return false
        }

        let defaults = UserDefaults.standard
        let oldKeys = [
            "SessionTimeout",
            "AutoLockOnBackground",
            "AutoLockEnabled",
            "AutoLockInterval",
            "AutoCloseEnabled",
            "AutoCloseInterval",
            "autoClearClipboard",
            "clearDelay",
            "Theme.name",
            "CryptoHelper.BiometricUnlockEnabled"
        ]

        return oldKeys.contains { defaults.object(forKey: $0) != nil }
    }

    private static func markMigrationComplete() {
        UserDefaults.standard.set(true, forKey: migrationKey)
        print("✅ Migration marked as complete")
    }

    // MARK: - Custom Settings Checks

    private static func hasCustomBiometricUnlock() -> Bool {
        CustomKeychainManager.shared.load(key: "SecureSetting.BiometricUnlockEnabled") != nil
    }

    private static func hasCustomTransparency() -> Bool {
        UserDefaults.standard.object(forKey: "Settings.transparencyEnabled") != nil
    }

    private static func hasCustomAutoLockOnBackground() -> Bool {
        CustomKeychainManager.shared.load(key: "SecureSetting.AutoLockOnBackground") != nil
    }

    private static func hasCustomAutoLockEnabled() -> Bool {
        CustomKeychainManager.shared.load(key: "SecureSetting.AutoLockEnabled") != nil
    }

    private static func hasCustomAutoLockInterval() -> Bool {
        CustomKeychainManager.shared.load(key: "SecureSetting.AutoLockInterval") != nil
    }

    private static func hasCustomAutoCloseEnabled() -> Bool {
        CustomKeychainManager.shared.load(key: "SecureSetting.AutoCloseEnabled") != nil
    }

    private static func hasCustomAutoCloseInterval() -> Bool {
        CustomKeychainManager.shared.load(key: "SecureSetting.AutoCloseInterval") != nil
    }

    private static func hasCustomAutoClearClipboard() -> Bool {
        CustomKeychainManager.shared.load(key: "SecureSetting.AutoClearClipboard") != nil
    }

    private static func hasCustomClearDelay() -> Bool {
        CustomKeychainManager.shared.load(key: "SecureSetting.ClearDelay") != nil
    }
}
