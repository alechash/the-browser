import SwiftUI
#if os(macOS)
import AppKit
#endif

#if os(macOS)
struct BrowserCommandContext {
    let openNewTab: () -> Void
    let closeCurrentTab: () -> Void
    let reopenLastClosedTab: () -> Void
    let selectNextTab: () -> Void
    let selectPreviousTab: () -> Void
    let reload: () -> Void
    let focusAddressBar: () -> Void
    let findOnPage: () -> Void
    let zoomIn: () -> Void
    let zoomOut: () -> Void
    let resetZoom: () -> Void
    let toggleContentFullscreen: () -> Void
    let canSelectNextTab: Bool
    let canSelectPreviousTab: Bool
    let canReopenLastClosedTab: Bool
    let hasActiveTab: Bool
}

private struct BrowserActionsKey: FocusedValueKey {
    typealias Value = BrowserCommandContext
}

extension FocusedValues {
    var browserActions: BrowserCommandContext? {
        get { self[BrowserActionsKey.self] }
        set { self[BrowserActionsKey.self] = newValue }
    }
}

struct BrowserCommands: Commands {
    @FocusedValue(\.browserActions) private var actions
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                openNewWindow()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Tab") {
                actions?.openNewTab()
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(actions == nil)
        }

        CommandMenu("Tabs") {
            Button("Close Tab") {
                actions?.closeCurrentTab()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(actions == nil || actions?.hasActiveTab == false)

            Button("Reopen Last Closed Tab") {
                actions?.reopenLastClosedTab()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(actions?.canReopenLastClosedTab != true)

            Button("Next Tab") {
                actions?.selectNextTab()
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .disabled(actions?.canSelectNextTab != true)

            Button("Previous Tab") {
                actions?.selectPreviousTab()
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            .disabled(actions?.canSelectPreviousTab != true)
        }

        CommandMenu("View") {
            Button("Reload Page") {
                actions?.reload()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(actions?.hasActiveTab != true)

            Divider()

            Button("Zoom In") {
                actions?.zoomIn()
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(actions?.hasActiveTab != true)

            Button("Zoom Out") {
                actions?.zoomOut()
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(actions?.hasActiveTab != true)

            Button("Actual Size") {
                actions?.resetZoom()
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(actions?.hasActiveTab != true)

            Divider()

            Button("Toggle Sidebar Fullscreen") {
                actions?.toggleContentFullscreen()
            }
            .keyboardShortcut("f", modifiers: [.command, .control])
        }

        CommandMenu("Navigate") {
            Button("Focus Address Bar") {
                actions?.focusAddressBar()
            }
            .keyboardShortcut("l", modifiers: .command)

            Button("Find on Page") {
                actions?.findOnPage()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(actions?.hasActiveTab != true)
        }
    }

    private func openNewWindow() {
        if #available(macOS 13.0, *) {
            openWindow(id: "browser")
        } else {
            guard let app = NSApp else { return }

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.contentView = NSHostingView(rootView: BrowserView())
            window.makeKeyAndOrderFront(nil)
            app.activate(ignoringOtherApps: true)
        }
    }
}
#endif
