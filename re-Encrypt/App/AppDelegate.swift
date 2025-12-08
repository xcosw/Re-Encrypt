import AppKit
import Darwin
import os.log
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        configureSecuritySettings()
    }

    private func configureSecuritySettings() {
        #if !DEBUG
        if let window = NSApplication.shared.windows.first {
            window.sharingType = .none
        }
        #endif
        configureWindowSecurity()
    }

    private func configureWindowSecurity() {
        DispatchQueue.main.async {
            for window in NSApplication.shared.windows {
                window.sharingType = .none
                #if !DEBUG
                window.level = .normal
                #endif
            }

            NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: nil,
                queue: .main
            ) { notification in
                if let window = notification.object as? NSWindow {
                    window.sharingType = .none
                    #if !DEBUG
                    window.level = .normal
                    #endif
                }
            }
        }
    }
}
