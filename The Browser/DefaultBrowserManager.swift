#if os(macOS)
import AppKit
import Combine
import CoreServices
import Security

@MainActor
final class DefaultBrowserManager: ObservableObject {
    @Published private(set) var isDefaultHandler: Bool = false
    @Published private(set) var currentHandlerName: String?
    @Published private(set) var currentHandlerIdentifier: String?
    @Published private(set) var lastErrorMessage: String?

    private let appBundleIdentifier: String
    private let appDisplayName: String

    init() {
        self.appBundleIdentifier = Bundle.main.bundleIdentifier ?? ""
        let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "The Browser"
        self.appDisplayName = displayName
        refresh()
    }

    func refresh() {
        guard !appBundleIdentifier.isEmpty else {
            isDefaultHandler = false
            currentHandlerIdentifier = nil
            currentHandlerName = nil
            return
        }

        let httpHandler = handlerIdentifier(for: "http")
        let httpsHandler = handlerIdentifier(for: "https")
        let effectiveHandler = httpHandler ?? httpsHandler

        isDefaultHandler = (httpHandler == appBundleIdentifier && httpsHandler == appBundleIdentifier)

        if isDefaultHandler {
            currentHandlerIdentifier = appBundleIdentifier
            currentHandlerName = appDisplayName
        } else {
            currentHandlerIdentifier = effectiveHandler
            if let identifier = effectiveHandler {
                currentHandlerName = applicationName(forBundleIdentifier: identifier) ?? identifier
            } else {
                currentHandlerName = nil
            }
        }
    }

    func setAsDefaultBrowser() {
        guard !appBundleIdentifier.isEmpty else { return }
        lastErrorMessage = nil

        let httpStatus = LSSetDefaultHandlerForURLScheme("http" as CFString, appBundleIdentifier as CFString)
        let httpsStatus = LSSetDefaultHandlerForURLScheme("https" as CFString, appBundleIdentifier as CFString)

        if httpStatus == noErr && httpsStatus == noErr {
            refresh()
        } else {
            let failingStatus = httpStatus != noErr ? httpStatus : httpsStatus
            lastErrorMessage = errorMessage(for: failingStatus)
            refresh()
        }
    }

    private func handlerIdentifier(for scheme: String) -> String? {
        guard let handler = LSCopyDefaultHandlerForURLScheme(scheme as CFString)?.takeRetainedValue() else {
            return nil
        }
        return handler as String
    }

    private func applicationName(forBundleIdentifier bundleIdentifier: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        return FileManager.default.displayName(atPath: url.path)
    }

    private func errorMessage(for status: OSStatus) -> String {
        if status == noErr { return "" }
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return message
        }
        return "An unknown error occurred (\(status))."
    }
}
#endif
