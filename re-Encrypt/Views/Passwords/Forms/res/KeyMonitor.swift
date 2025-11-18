import SwiftUI

class KeyMonitor: ObservableObject {
    @MainActor static let shared = KeyMonitor()
    @Published var key: UInt16? = nil
    
    private var monitor: Any?
    
    private init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.key = event.keyCode
            return event
        }
    }
    
    deinit {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
