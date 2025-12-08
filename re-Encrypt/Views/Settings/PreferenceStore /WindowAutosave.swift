import SwiftUI
import AppKit

private final class WindowResolverView: NSView {
    var onResolve: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = self.window {
            onResolve?(window)
        }
    }
}

struct WindowAccessor: NSViewRepresentable {
    var onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = WindowResolverView()
        v.onResolve = onResolve
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) { }
}

private struct WindowFrameAutosaveModifier: ViewModifier {
    let autosaveName: String

    func body(content: Content) -> some View {
        content
            .background(
                WindowAccessor { window in
                    window.setFrameAutosaveName(autosaveName)
                }
                .frame(width: 0, height: 0)
            )
    }
}

extension View {
    func windowFrameAutosave(_ name: String) -> some View {
        self.modifier(WindowFrameAutosaveModifier(autosaveName: name))
    }
}
