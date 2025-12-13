//
//  MemoryProtector.swift
//  re-Encrypt
//
//  Created by xcosw.dev on 13.12.2025.
//

import Foundation
import os.log
// MARK: - ========================================
// MARK: - 5. MEMORY PROTECTOR (Actor)
// MARK: - ========================================

@available(macOS 15.0, *)
actor MemoryProtector {
    static let shared = MemoryProtector()
    
    private var protectedRegions: [UnsafeMutableRawPointer] = []
    
    private init() {}
    
    func protectMemory(_ data: Data) -> Bool {
        return data.withUnsafeBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress else { return false }
            let mutableAddress = UnsafeMutableRawPointer(mutating: baseAddress)
            
            // Lock memory to prevent swapping to disk
            let mlockResult = mlock(baseAddress, buffer.count)
            guard mlockResult == 0 else {
                secureLog("❌ Failed to mlock memory", level: .error)
                return false
            }
            
            // Mark as non-dumpable (macOS specific)
            #if !DEBUG
            var protection = vm_prot_t(VM_PROT_READ | VM_PROT_WRITE)
            let result = vm_protect(
                mach_task_self_,
                vm_address_t(bitPattern: baseAddress),
                vm_size_t(buffer.count),
                0,
                protection
            )
            
            if result != KERN_SUCCESS {
                secureLog("⚠️ vm_protect failed", level: .error)
            }
            #endif
            
            protectedRegions.append(mutableAddress)
            return true
        }
    }
    
    func hasProtectedRegions() -> Bool {
            return !protectedRegions.isEmpty
        }
    
    func cleanup() {
        for address in protectedRegions {
            munlock(address, MemoryLayout<UInt8>.size)
        }
        protectedRegions.removeAll()
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
