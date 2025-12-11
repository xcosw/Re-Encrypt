//
//  NativeMessageHost.swift
//  re-Encrypt
//
//  Created by xcosw.dev on 11.12.2025.
//

import Foundation

// MARK: - Native Messaging Host Functions

@available(macOS 15.0, *)
@MainActor
struct NativeMessageHost {
    
    /// Entry point for the Native Messaging host process.
    static func run() {
        // Use FileHandle.standardInput for reading from the browser's pipe
        let input = FileHandle.standardInput
        
        while true {
            // 1. Read the 4-byte message length
            guard let lengthData = try? input.read(upToCount: 4), lengthData.count == 4 else {
                // Connection closed or invalid read
                break
            }
            
            // Convert lengthData (little-endian UInt32) to Int
            let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
            
            // 2. Read the JSON message payload
            guard let messageData = try? input.read(upToCount: Int(length)), messageData.count == Int(length) else {
                break
            }
            
            handleMessage(messageData: messageData)
        }
    }
    
    /// Handles decoding, processing, and responding to a single request.
    private static func handleMessage(messageData: Data) {
        do {
            let request = try JSONDecoder().decode(ExtensionRequest.self, from: messageData)
            
            // --- Core Business Logic: Password Lookup ---
            let response = processRequest(request: request)
            
            // --- Send Response ---
            sendResponse(response: response)
            
        } catch {
            let errorResponse = ExtensionResponse(
                action: "error",
                username: nil,
                password: nil,
                error: "Failed to decode request: \(error.localizedDescription)"
            )
            sendResponse(response: errorResponse)
        }
    }
    
    /// Looks up credentials and generates the successful response.
    private static func processRequest(request: ExtensionRequest) -> ExtensionResponse {
        // **TODO: Implement your Core Data lookup here**
        
        // This is a dummy implementation. Replace with actual Core Data lookup:
        // 1. Find the entry based on request.url (requires a function in CoreDataHelper)
        // 2. Decrypt the password (using CoreDataHelper.decryptedPasswordString)
        
        let dummyUsername = "testuser"
        let dummyPassword = "securepassword123"

        // NOTE: In a real app, you would securely load the decrypted data
        // into a SecureDataBuffer/SecData instance, use it, and let it clear.
        
        return ExtensionResponse(
            action: "autofill",
            username: dummyUsername,
            password: dummyPassword,
            error: nil
        )
    }
    
    /// Encodes and writes the response back to the browser via stdout.
    private static func sendResponse(response: ExtensionResponse) {
        guard let jsonData = try? JSONEncoder().encode(response) else {
            // Cannot encode response, cannot report error
            return
        }
        
        let output = FileHandle.standardOutput
        let length = UInt32(jsonData.count).littleEndian
        var lengthData = length.data // Convert length to Data for writing
        
        // Write the 4-byte little-endian length prefix
        output.write(lengthData)
        
        // Write the JSON payload
        output.write(jsonData)
        
        // Ensure data is immediately sent
        output.synchronizeFile()
    }
}

// Small helper to get Data from UInt32
extension UInt32 {
    var data: Data {
        var value = self.littleEndian // Ensure little-endian format
        return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
    }
}
