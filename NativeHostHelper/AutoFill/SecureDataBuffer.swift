//
//  SecureDataBuffer.swift
//  re-Encrypt
//
//  Created by xcosw.dev on 11.12.2025.
//

import Foundation

// MARK: - Native Messaging Data Contracts

// Request received from the browser extension
struct ExtensionRequest: Codable {
    let url: String
    let action: String? // e.g., "lookup"
}

// Response sent back to the browser extension
struct ExtensionResponse: Codable {
    let action: String // e.g., "autofill"
    let username: String?
    let password: String?
    let error: String?
}

// Helper to access data buffers safely (Crucial for clearing sensitive data)
class SecureDataBuffer {
    var data: Data
    
    init(_ data: Data) {
        self.data = data
    }
    
    deinit {
        // Attempt to zero-out memory when object is destroyed
        data.withUnsafeMutableBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            memset_s(base, ptr.count, 0, ptr.count)
        }
    }
}
