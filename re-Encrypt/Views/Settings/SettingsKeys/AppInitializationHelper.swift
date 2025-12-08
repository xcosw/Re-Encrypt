//
//  AppInitializationHelper.swift
//  re-Encrypt
//
//  Created by xcosw.dev on 3.12.2025.
//

import Foundation

@available(macOS 15.0, *)
@MainActor
public struct AppInitializationHelper {
    
    public static func initialize() {
        print("🚀 Initializing app...")
        CryptoHelper.initializeLocalBackend()
        print("✅ App initialization complete")
    }
    
    public static func initializeSecureSettings() {
        print("🔐 Loading secure settings after unlock...")
        
        // Reload security config
        SecurityConfigManager.shared.reload()
        
        // Load monitoring settings AFTER vault is unlocked
        MemoryPressureMonitor.shared.loadSettings()
        ScreenshotDetectionManager.shared.loadSettings()
        
        print("✅ Secure settings and monitors loaded")
    }
}
