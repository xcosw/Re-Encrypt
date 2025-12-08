import Foundation

// MARK: - Data Security Extensions

extension Data {
    
    /// Securely wipe data from memory
    /*mutating func secureWipe() {
        self.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress, buffer.count > 0 else { return }
            
            // Triple overwrite pattern (DoD 5220.22-M)
            // Pass 1: Write zeros
            _ = memset_s(base, buffer.count, 0x00, buffer.count)
            
            // Pass 2: Write ones
            _ = memset_s(base, buffer.count, 0xFF, buffer.count)
            
            // Pass 3: Write random
            var randomData = Data(count: buffer.count)
            _ = randomData.withUnsafeMutableBytes {
                SecRandomCopyBytes(kSecRandomDefault, buffer.count, $0.baseAddress!)
            }
            randomData.copyBytes(to: buffer)
            
            // Final pass: zeros
            _ = memset_s(base, buffer.count, 0x00, buffer.count)
            
            // Clear the random data too
            randomData.withUnsafeMutableBytes { randomBuffer in
                if let randomBase = randomBuffer.baseAddress {
                    _ = memset_s(randomBase, randomBuffer.count, 0x00, randomBuffer.count)
                }
            }
        }
        
        // Reset to empty
        self = Data()
    }*/
    
    /// Check if data appears to be encrypted (high entropy)
    var appearsEncrypted: Bool {
        guard count > 16 else { return false }
        
        // Calculate byte frequency
        var frequencies = [UInt8: Int]()
        for byte in self {
            frequencies[byte, default: 0] += 1
        }
        
        // Good encryption should have relatively uniform distribution
        let avgFrequency = Double(count) / 256.0
        let variance = frequencies.values.reduce(0.0) { result, freq in
            let diff = Double(freq) - avgFrequency
            return result + (diff * diff)
        }
        
        // Low variance indicates high entropy (likely encrypted)
        let normalizedVariance = variance / Double(count)
        return normalizedVariance < 50.0
    }
    
    /// Create a copy that can be securely cleared
    func secureCopy() -> Data {
        return Data(self)
    }
}

// MARK: - String Security Extensions

extension String {
    
    /// Securely clear string from memory (creates mutable copy and wipes it)
    mutating func secureClear() {
        var data = Data(self.utf8)
        data.secureWipe()
        self = ""
    }
    
    /// Check if string is likely a TOTP secret (Base32)
    var isTOTPSecret: Bool {
        let cleaned = self.uppercased().replacingOccurrences(of: " ", with: "")
        let base32Charset = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567=")
        return !cleaned.isEmpty &&
               cleaned.count >= 16 &&
               cleaned.rangeOfCharacter(from: base32Charset.inverted) == nil
    }
    
    /// Check if string is otpauth:// URL
    var isOTPAuthURL: Bool {
        return self.lowercased().hasPrefix("otpauth://totp/")
    }
}

// MARK: - Secure Memory Allocator

final class SecureMemoryAllocator {
    
    /// Allocate secure memory block (locked from swapping)
    static func allocate(size: Int) -> UnsafeMutableRawPointer? {
        guard size > 0, size <= 1_048_576 else { return nil } // Max 1MB
        
        let pointer = malloc(size)
        
        guard let ptr = pointer else { return nil }
        
        // Lock memory to prevent swapping to disk
        if mlock(ptr, size) != 0 {
            #if DEBUG
            print("⚠️ Warning: Could not lock memory (errno: \(errno))")
            #endif
        }
        
        // Zero out the memory
        memset(ptr, 0, size)
        
        return ptr
    }
    
    /// Securely deallocate memory
    static func deallocate(_ pointer: UnsafeMutableRawPointer, size: Int) {
        // Overwrite with zeros
        _ = memset_s(pointer, size, 0, size)
        
        // Unlock memory
        munlock(pointer, size)
        
        // Free
        free(pointer)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let masterPasswordChanged = Notification.Name("com.passwordmanager.masterPasswordChanged")
    static let totpSecretAdded = Notification.Name("com.passwordmanager.totpSecretAdded")
    static let totpSecretRemoved = Notification.Name("com.passwordmanager.totpSecretRemoved")
}
