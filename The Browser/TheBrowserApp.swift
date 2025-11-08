import SwiftUI

@main
struct TheBrowserApp: App {
    var body: some Scene {
        WindowGroup(id: "browser") {
            BrowserView()
        }
#if os(macOS)
        .handlesExternalEvents(matching: ["*"])
        .commands {
            BrowserCommands()
        }
#endif
    }
}
