//
//  MemoryPressureMonitor.swift
//  re-Encrypt
//
//  Created by xcosw.dev on 18.11.2025.
//

import Foundation

@MainActor
// MARK: - Memory Pressure Monitor
final class MemoryPressureMonitor: ObservableObject {
    static let shared = MemoryPressureMonitor()
    @Published var isUnderPressure = false
    private var source: DispatchSourceMemoryPressure?

    private init() {
        setupMonitoring()
    }

    private func setupMonitoring() {
        source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source?.setEventHandler { [weak self] in
            guard let self = self, let src = self.source else { return }
            let event = src.data
            if event.contains(.warning) {
                self.isUnderPressure = true
                self.handleMemoryPressure()
            }
            if event.contains(.critical) {
                self.isUnderPressure = true
                self.handleCriticalMemoryPressure()
            }
        }
        source?.resume()
    }

    private func handleMemoryPressure() {
        SecureClipboard.shared.clearClipboard()
        NotificationCenter.default.post(name: .memoryPressureDetected, object: nil)
    }

    private func handleCriticalMemoryPressure() {
        CryptoHelper.clearKeys()
        NotificationCenter.default.post(name: .sessionExpired, object: nil)
    }
}
