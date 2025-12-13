//
//  MemoryPressureMonitor.swift
//  re-Encrypt
//
//  Created by xcosw.dev on 18.11.2025.
//

import Foundation

@available(macOS 15.0, *)
@MainActor
final class MemoryPressureMonitor: ObservableObject {
    static let shared = MemoryPressureMonitor()
    
    @Published var isUnderPressure = false
    @Published var isEnabled = true {
        didSet {
            if isEnabled != oldValue {
                Task {
                    await
                CryptoHelper.setMemoryPressureMonitoringEnabled(isEnabled)
                applySettings()
            } }
        }
    }
    
    @Published var autoLockOnPressure = true {
        didSet {
            if autoLockOnPressure != oldValue {
                Task {
                    await
                CryptoHelper.setMemoryPressureAutoLock(autoLockOnPressure)
            }}
        }
    }
    
    private var source: DispatchSourceMemoryPressure?
    
    private init() {
        setupMonitoring()
        
        // Listen for settings changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadSettings),
            name: .memoryPressureSettingsChanged,
            object: nil
        )
    }
    
    func loadSettings() async {
        // Only load if vault is unlocked
        guard await CryptoHelper.isUnlocked else {
            print("⚠️ Vault locked - using default memory monitoring settings")
            return
        }
        
        isEnabled = await CryptoHelper.getMemoryPressureMonitoringEnabled()
        autoLockOnPressure = await CryptoHelper.getMemoryPressureAutoLock()
        print("📋 Memory monitoring loaded: enabled=\(isEnabled), autoLock=\(autoLockOnPressure)")
    }
    
    @objc private func reloadSettings() async {
        await loadSettings()
        applySettings()
    }
    
    private func applySettings() {
        if isEnabled {
            setupMonitoring()
        } else {
            source?.cancel()
            source = nil
            print("⏸️ Memory pressure monitoring disabled")
        }
    }
    
    private func setupMonitoring() {
        guard isEnabled else { return }
        
        source?.cancel()
        source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        
        source?.setEventHandler { [weak self] in
            guard let self = self, let src = self.source else { return }
            let event = src.data
            
            if event.contains(.warning) {
                Task { // <-- wrap async work here
                       await  self.handleMemoryWarning()
                   }
            }
            if event.contains(.critical) {
                Task { // <-- wrap async work here
                       await  self.handleCriticalMemoryPressure()
                   }
            }
        }
        
        source?.resume()
        print("✅ Memory pressure monitoring enabled")
    }
    
    private func handleMemoryWarning() async {
        isUnderPressure = true
        await SecureClipboard.shared.clearClipboard()
        print("⚠️ Memory pressure warning")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.isUnderPressure = false
        }
    }
    
    private func handleCriticalMemoryPressure() async {
        isUnderPressure = true
        print("🚨 Critical memory pressure")
        
        await SecureClipboard.shared.clearClipboard()
        
        if autoLockOnPressure {
            await CryptoHelper.clearKeys()
            NotificationCenter.default.post(name: .sessionExpired, object: nil)
        }
        
        NotificationCenter.default.post(name: .memoryPressureDetected, object: nil)
    }
    
    @MainActor
    deinit {
        NotificationCenter.default.removeObserver(self)
        source?.cancel()
    }
}
