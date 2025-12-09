# re-Encrypt — Military-Grade Password Manager for macOS

**Your passwords. Truly yours. Never compromised.**

`re-Encrypt` is a **native, offline-first, zero-knowledge** password manager built exclusively for macOS with **paranoid-level security** in mind.

No cloud. No telemetry. No backdoors. Just unbreakable encryption and total control.

<img src="https://raw.githubusercontent.com/yourusername/re-Encrypt/main/.github/screenshot.png" alt="re-Encrypt Lock Screen" width="100%"/>

> **Warning: This is not your average password manager.**  
> It's built for people who understand that most "secure" apps are just security theater.

---

### Security Highlights

| Feature                            | Implementation                                                                 |
|------------------------------------|---------------------------------------------------------------------------------|
| Master Key Derivation              | Argon2id (RFC 9106) via custom high-performance implementation                  |
| In-Memory Key Storage              | `mlock()`-protected, page-locked, zeroed on free (`SecData` wrapper)           |
| Encryption                         | AES-256-GCM with per-entry unique salts + device binding                        |
| Key Hierarchy                      | HKDF-SHA256 key separation (master → entry → settings → HMAC)                   |
| Device Binding                     | Hardware UUID + Serial + MAC + CPU model + secure enclave-bound fallback       |
| Anti-Tampering                     | Code signing validation, debugger detection, VM detection                      |
| Secure Wipe                        | Overwrite-with-random + `memset_s` + atomic file protection                     |
| Session Management                 | Configurable timeout, auto-lock, memory pressure auto-wipe                      |
| Biometric Unlock                   | Face ID / Touch ID via Keychain (password still required on first unlock)       |
| Failed Attempt Protection          | Exponential backoff + full data wipe after 5 failed attempts                    |
| Screenshot Protection              | Detects and logs screenshots (optional auto-lock)                               |
| No Plaintext Ever Leaves Memory    | All passwords decrypted only in protected memory, cleared immediately after use |

---

### Technical Stack

- **Swift 5.9+** & **SwiftUI** (macOS 15+)
- **CryptoKit** + **CommonCrypto**
- Custom **Argon2id** implementation (xCore — pure Swift, no C dependencies)
- Full **Blake2b** implementation for Argon2id
- Zero external dependencies
- Fully async/await & `@MainActor` safe

---

### Features

- Beautiful native macOS design (Sonoma+ ready)
- Full keyboard navigation & accessibility
- Secure auto-fill (via companion browser extension — coming soon)
- Folder organization
- Customizable themes
- Secure notes
- TOTP 2FA support (coming soon)
- Import from 1Password, Bitwarden, LastPass (planned)
- Full offline operation

---

### Why Another Password Manager?

Because **none of the popular ones are truly secure on macOS**:

| App              | Stores Master Key in Memory? | Argon2id? | Device Binding? | Open Source? | Native SwiftUI? |
|------------------|------------------------------|-----------|------------------|--------------|-----------------|
| 1Password        | No (Electron)                | No        | Partial          | No           | No              |
| Bitwarden        | No (web tech)                | Partial   | No               | Yes          | No              |
| Strongbox        | Yes                          | Yes       | No               | Yes          | Partial         |
| **re-Encrypt**   | **Yes**                      | **Yes**   | **Yes**          | **Yes**     | **Yes**         |

---

### Building

```bash
git clone https://github.com/xcosw/re-Encrypt.git
cd re-Encrypt
open re-Encrypt.xcodeproj
