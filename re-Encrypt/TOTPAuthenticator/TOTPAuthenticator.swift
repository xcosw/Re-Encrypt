import Foundation
import CryptoKit
import CommonCrypto

// MARK: - TOTP Authenticator (for storing codes in password entries)
// NOTE: This is SEPARATE from app's 2FA lock system

/// Generates TOTP codes for password entries (RFC 6238)
struct TOTPAuthenticator {
    
    /// Generate 6-digit TOTP code from secret
    static func generateCode(secret: String, timeInterval: TimeInterval = 30, digits: Int = 6) -> String? {
        guard let secretData = base32Decode(secret) else {
            return nil
        }
        
        let counter = UInt64(Date().timeIntervalSince1970 / timeInterval)
        return generateHOTP(secret: secretData, counter: counter, digits: digits)
    }
    
    /// Get remaining seconds until code expires
    static func getRemainingSeconds(timeInterval: TimeInterval = 30) -> Int {
        let now = Date().timeIntervalSince1970
        let remaining = timeInterval - now.truncatingRemainder(dividingBy: timeInterval)
        return Int(remaining)
    }
    
    /// Calculate progress (0.0 to 1.0) for circular progress indicator
    static func getProgress(timeInterval: TimeInterval = 30) -> Double {
        let remaining = Double(getRemainingSeconds(timeInterval: timeInterval))
        return remaining / timeInterval
    }
    
    // MARK: - HOTP Implementation (RFC 4226)
    
    private static func generateHOTP(secret: Data, counter: UInt64, digits: Int) -> String? {
        var bigCounter = counter.bigEndian
        let counterData = Data(bytes: &bigCounter, count: MemoryLayout<UInt64>.size)
        
        guard let hmac = hmacSHA1(key: secret, data: counterData) else {
            return nil
        }
        
        let offset = Int(hmac[hmac.count - 1] & 0x0f)
        let truncatedHash = hmac.subdata(in: offset..<offset+4)
        
        var number = truncatedHash.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        number &= 0x7fffffff
        number = number % UInt32(pow(10, Float(digits)))
        
        return String(format: "%0\(digits)d", number)
    }
    
    private static func hmacSHA1(key: Data, data: Data) -> Data? {
        var hmac = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        
        key.withUnsafeBytes { keyBytes in
            data.withUnsafeBytes { dataBytes in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA1),
                       keyBytes.baseAddress, key.count,
                       dataBytes.baseAddress, data.count,
                       &hmac)
            }
        }
        
        return Data(hmac)
    }
    
    // MARK: - Base32 Decoder
    
    private static func base32Decode(_ string: String) -> Data? {
        let base32Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        var cleanedString = string.uppercased().replacingOccurrences(of: " ", with: "")
        cleanedString = cleanedString.replacingOccurrences(of: "=", with: "")
        
        var bits = ""
        for char in cleanedString {
            guard let index = base32Alphabet.firstIndex(of: char) else {
                return nil
            }
            let value = base32Alphabet.distance(from: base32Alphabet.startIndex, to: index)
            bits += String(value, radix: 2).leftPadding(toLength: 5, withPad: "0")
        }
        
        var bytes = [UInt8]()
        for i in stride(from: 0, to: bits.count, by: 8) {
            let endIndex = min(i + 8, bits.count)
            let byteString = String(bits[bits.index(bits.startIndex, offsetBy: i)..<bits.index(bits.startIndex, offsetBy: endIndex)])
            if byteString.count == 8, let byte = UInt8(byteString, radix: 2) {
                bytes.append(byte)
            }
        }
        
        return Data(bytes)
    }
}

// MARK: - String Extension for Padding

private extension String {
    func leftPadding(toLength: Int, withPad: String) -> String {
        guard self.count < toLength else { return self }
        return String(repeating: withPad, count: toLength - self.count) + self
    }
}

// MARK: - TOTP URL Parser (for otpauth:// URLs)

struct OTPAuthURLParser {
    
    /// Parse otpauth:// URL
    static func parse(_ urlString: String) -> (secret: String, issuer: String?, account: String?)? {
        guard let url = URL(string: urlString),
              url.scheme == "otpauth",
              url.host == "totp" else {
            return nil
        }
        
        let account = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return nil
        }
        
        var secret: String?
        var issuer: String?
        
        for item in queryItems {
            switch item.name.lowercased() {
            case "secret":
                secret = item.value
            case "issuer":
                issuer = item.value
            default:
                break
            }
        }
        
        guard let validSecret = secret, !validSecret.isEmpty else {
            return nil
        }
        
        return (validSecret, issuer, account.isEmpty ? nil : account)
    }
    
    /// Validate Base32 secret format
    static func isValidSecret(_ secret: String) -> Bool {
        let cleaned = secret.uppercased().replacingOccurrences(of: " ", with: "")
        let base32Charset = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567=")
        return cleaned.rangeOfCharacter(from: base32Charset.inverted) == nil
    }
}

struct TOTPURLParser {
    
    /// Parse otpauth:// URL
    static func parse(_ urlString: String) -> (secret: String, issuer: String?, account: String?)? {
        guard let url = URL(string: urlString),
              url.scheme == "otpauth",
              url.host == "totp" else {
            return nil
        }
        
        // Extract account from path
        let account = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        // Parse query parameters
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return nil
        }
        
        var secret: String?
        var issuer: String?
        
        for item in queryItems {
            switch item.name.lowercased() {
            case "secret":
                secret = item.value
            case "issuer":
                issuer = item.value
            default:
                break
            }
        }
        
        guard let validSecret = secret, !validSecret.isEmpty else {
            return nil
        }
        
        return (validSecret, issuer, account.isEmpty ? nil : account)
    }
    
    /// Validate Base32 secret format
    static func isValidSecret(_ secret: String) -> Bool {
        let cleaned = secret.uppercased().replacingOccurrences(of: " ", with: "")
        let base32Charset = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567=")
        return cleaned.rangeOfCharacter(from: base32Charset.inverted) == nil
    }
}
