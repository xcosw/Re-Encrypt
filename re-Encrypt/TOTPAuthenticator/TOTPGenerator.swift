import Foundation
import CoreData
import CryptoKit

// MARK: - TOTP Generator for Password Entries

class TOTPGenerator {
    
    /// Generate a TOTP code from a secret
    static func generateCode(secret: String, timeInterval: TimeInterval = Date().timeIntervalSince1970) -> String? {
        guard let secretData = base32Decode(secret) else {
            return nil
        }
        
        let timeSlice = Int(timeInterval / 30) // 30-second windows
        return generateTOTP(secret: secretData, timeSlice: timeSlice)
    }
    
    /// Get remaining seconds in current time window
    static func getRemainingSeconds() -> Int {
        let now = Date().timeIntervalSince1970
        return 30 - Int(now.truncatingRemainder(dividingBy: 30))
    }
    
    /// Get progress (0.0 to 1.0) in current time window
    static func getProgress() -> Double {
        let remaining = Double(getRemainingSeconds())
        return remaining / 30.0
    }
    
    // MARK: - Private Helpers
    
    private static func generateTOTP(secret: Data, timeSlice: Int) -> String {
        // Convert time slice to 8-byte big-endian
        var counter = UInt64(timeSlice).bigEndian
        let counterData = Data(bytes: &counter, count: 8)
        
        // HMAC-SHA1
        let key = SymmetricKey(data: secret)
        let hmac = HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: key)
        let hmacData = Data(hmac)
        
        // Dynamic truncation
        let offset = Int(hmacData[hmacData.count - 1] & 0x0f)
        let truncatedHash = hmacData.subdata(in: offset..<offset + 4)
        
        var value = UInt32(bigEndian: truncatedHash.withUnsafeBytes { $0.load(as: UInt32.self) })
        value &= 0x7fffffff
        value %= 1_000_000
        
        return String(format: "%06d", value)
    }
    
    private static func base32Decode(_ string: String) -> Data? {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        var result = Data()
        var bits = 0
        var buffer = 0
        
        for char in string.uppercased() {
            guard let index = alphabet.firstIndex(of: char) else { continue }
            let value = alphabet.distance(from: alphabet.startIndex, to: index)
            
            buffer = (buffer << 5) | value
            bits += 5
            
            if bits >= 8 {
                bits -= 8
                result.append(UInt8((buffer >> bits) & 0xFF))
            }
        }
        
        return result
    }
}
