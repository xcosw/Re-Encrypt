import SwiftUI

@MainActor
class KeyMonitor: ObservableObject {
    static let shared = KeyMonitor()
    @Published var key: UInt16? = nil
    
    private var monitor: Any?
    
    private init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.key = event.keyCode
            return event
        }
    }
    
    @MainActor
    deinit {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
