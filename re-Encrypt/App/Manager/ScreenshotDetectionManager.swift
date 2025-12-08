//
//  ScreenshotDetectionManager.swift
//  re-Encrypt
//
//  Created by xcosw.dev on 3.12.2025.
//

import Foundation
import AppKit
import UserNotifications

@available(macOS 15.0, *)
@MainActor
final class ScreenshotDetectionManager: ObservableObject {
    static let shared = ScreenshotDetectionManager()
    
    @Published var isEnabled = true {
        didSet {
            if isEnabled != oldValue {
                CryptoHelper.setScreenshotDetectionEnabled(isEnabled)
                applySettings()
            }
        }
    }
    
    @Published var notificationsEnabled = true {
        didSet {
            if notificationsEnabled != oldValue {
                CryptoHelper.setScreenshotNotificationsEnabled(notificationsEnabled)
            }
        }
    }
    
    @Published var lastScreenshotTime: Date?
    
    private var observer: NSObjectProtocol?
    
    private init() {
        setupObserver()
        
        // Listen for settings changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadSettings),
            name: .screenshotSettingsChanged,
            object: nil
        )
    }
    
    func loadSettings() {
        // Only load if vault is unlocked
        guard CryptoHelper.isUnlocked else {
            print("⚠️ Vault locked - using default screenshot detection settings")
            return
        }
        
        isEnabled = CryptoHelper.getScreenshotDetectionEnabled()
        notificationsEnabled = CryptoHelper.getScreenshotNotificationsEnabled()
        print("📋 Screenshot detection loaded: enabled=\(isEnabled), notifications=\(notificationsEnabled)")
    }
    
    @objc private func reloadSettings() {
        loadSettings()
        applySettings()
    }
    
    private func applySettings() {
        if isEnabled {
            setupObserver()
        } else {
            if let obs = observer {
                DistributedNotificationCenter.default().removeObserver(obs)
                observer = nil
            }
            print("⏸️ Screenshot detection disabled")
        }
    }
    
    private func setupObserver() {
        guard isEnabled else { return }
        
        // Remove existing observer
        if let obs = observer {
            DistributedNotificationCenter.default().removeObserver(obs)
        }
        
        // Add new observer
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screencapture.didTakeScreenshot"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleScreenshotDetected()
            }
            
        }
        
        print("✅ Screenshot detection enabled")
    }
    
    private func handleScreenshotDetected() {
        guard isEnabled else { return } // <<< early return
        
        lastScreenshotTime = Date()
        print("📸 Screenshot detected at \(Date())")
        
        if notificationsEnabled {
            showNotification()
        }
        
        NotificationCenter.default.post(
            name: .screenshotDetected,
            object: nil
        )
    }

    
    private func showNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Security Alert"
        content.subtitle = "Screenshot Detected"
        content.body = "A screenshot was taken while viewing sensitive data."
        content.sound = .defaultCritical
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    @MainActor
    deinit {
        if let obs = observer {
            DistributedNotificationCenter.default().removeObserver(obs)
        }
        NotificationCenter.default.removeObserver(self)
    }
}
