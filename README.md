# Password Manager (Swift / macOS)

A secure, modern, native macOS password manager written entirely in
**Swift** and **SwiftUI**, featuring strong encryption, biometric
unlock, TOTP (2FA) support, and a clean Apple‑style interface.

------------------------------------------------------------------------

## 🔐 Core Security Features

### **AES‑256 Encryption**

All password entries and sensitive data are encrypted using
industry‑standard **AES‑256**.\
The encryption logic is implemented inside:

-   `CryptoHelper.swift`
-   `SecurePasswordStorage.swift`
-   `SecData.swift`
-   `CryproHelper.swift` (older version)

### **PBKDF2 Key Derivation**

The master password is converted into a secure encryption key using
PBKDF2 with a high iteration count.

### **Biometric Unlock (Touch ID / Face ID)**

Located in: - `BiometricManager.swift`

Supports macOS biometric unlock for faster, secure access.

### **Secure Memory Handling**

The app includes:

-   `MemoryPressureMonitor.swift`\
    Automatically wipes sensitive memory if the system becomes
    constrained.

-   Temporary files are encrypted or wiped where appropriate.

------------------------------------------------------------------------

## 🔑 Password Management Features

### **Folder & Item Organization**

The project structure shows support for:

-   Multiple password entries
-   Editing and updating fields
-   Securing items individually
-   App settings and encryption reset

### **Two‑Factor Authentication (TOTP)**

Full built‑in TOTP authenticator:

-   `TOTPGenerator.swift`
-   `TOTPAuthenticator.swift`
-   `TwoFactorSettingsView.swift`
-   `TwoFactorSetupView.swift`
-   `AddTOTPSecretView.swift`
-   `TOTPDisplayView.swift`

This enables:

-   Adding TOTP secrets\
-   Displaying rotating 6‑digit codes\
-   Managing 2FA for multiple logins

------------------------------------------------------------------------

## 🖥 macOS Native UI

Located under `re-Encrypt/Views/`:

### **SwiftUI Interface Includes:**

-   Settings window (`SettingsView.swift`)
-   Theme customization
-   TOTP views\
-   Clean, Apple‑native layout\
-   AppIcon and color assets in `Assets.xcassets`

The UI is designed to be minimal, intuitive, and secure.

------------------------------------------------------------------------

## 📁 Project Structure

    Password Manager/
     ├── core/
     │    ├── core.swift
     │    ├── Xcosw/
     │    │    ├── CryptoHelper.swift
     │    │    ├── SecData.swift
     │    │    ├── AppInitializationHelper.swift
     │    │    ├── BiometricManager.swift
     │    │    ├── MemoryPressureMonitor.swift
     │    │    └── SecurePasswordStorage.swift
     │    └── core.docc/
     │         └── core.md
     ├── re-Encrypt.xcodeproj
     ├── re-Encrypt/
     │    ├── Views/
     │    ├── 2FA/
     │    ├── TOTPAuthenticator/
     │    ├── Assets.xcassets/
     │    └── Settings/
     └── ...

------------------------------------------------------------------------

## 🚀 How to Build

### **Requirements**

-   macOS 13 or later
-   Xcode 15+
-   Swift 5.9+

### **Steps**

1.  Clone the repository\
2.  Open `re-Encrypt.xcodeproj` in Xcode\
3.  Build & run the app

------------------------------------------------------------------------

## 🔮 Roadmap Ideas

-   iCloud syncing ?
-   Safari/Chrome autofill extension
-   Secure notes support
-   Password generator
-   Export/import encrypted vaults

------------------------------------------------------------------------

## 🛡 License

MIT License

Copyright (c) [2025] [XcoSw]

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

// Copyright (c) 2025 XcoSw
// Licensed under the MIT License
------------------------------------------------------------------------

## ❤️ Credits

Created with Swift, SwiftUI, and a focus on strong encryption and clean
macOS design.
