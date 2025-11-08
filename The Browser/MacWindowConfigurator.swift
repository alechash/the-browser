import SwiftUI
#if os(macOS)
import AppKit

struct MacWindowConfigurator: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        configureIfPossible(view, context: context)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configureIfPossible(nsView, context: context)
    }

    private func configureIfPossible(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.configure(window: window)
        }
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []
        private var didSetInitialFrame = false

        deinit {
            removeObservers()
        }

        func configure(window: NSWindow) {
            applyConfiguration(to: window)

            if self.window !== window {
                removeObservers()
                self.window = window
                window.delegate = self

                let notificationNames: [Notification.Name] = [
                    NSWindow.didBecomeKeyNotification,
                    NSWindow.didDeminiaturizeNotification,
                    NSWindow.didExitFullScreenNotification,
                    NSWindow.didEnterFullScreenNotification,
                    NSWindow.didMiniaturizeNotification,
                    NSWindow.didResizeNotification,
                    NSWindow.didMoveNotification
                ]

                observers = notificationNames.map { name in
                    NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        guard let self, let window = self.window else { return }
                        self.applyConfiguration(to: window)
                    }
                }
            }
        }

        func windowDidEndLiveResize(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            applyConfiguration(to: window)
        }

        func windowDidEnterFullScreen(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            applyConfiguration(to: window)
        }

        func windowDidExitFullScreen(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            applyConfiguration(to: window)
        }

        private func applyConfiguration(to window: NSWindow) {
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isMovableByWindowBackground = true
            window.title = ""
            window.toolbar = nil

            if !didSetInitialFrame {
                didSetInitialFrame = true
                if let screen = window.screen ?? NSScreen.main {
                    window.setFrame(screen.visibleFrame, display: true)
                }
            }

            if let titlebarContainer = window.contentView?.superview?.subviews.first(where: { String(describing: type(of: $0)).contains("NSTitlebar") }) {
                titlebarContainer.isHidden = true
                titlebarContainer.alphaValue = 0
                titlebarContainer.frame = .zero
            }
        }

        private func removeObservers() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
        }
    }
}
#endif
