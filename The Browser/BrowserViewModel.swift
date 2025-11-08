import SwiftUI
import WebKit
import Combine
#if os(macOS)
import AppKit
#endif

@MainActor
final class BrowserViewModel: NSObject, ObservableObject {
    struct TabState: Identifiable, Equatable {
        enum Kind: Equatable {
            case nativeHome
            case web
        }

        let id: UUID
        var title: String
        var addressBarText: String
        var canGoBack: Bool
        var canGoForward: Bool
        var isLoading: Bool
        var progress: Double
        var currentURL: URL?
        var kind: Kind
    }

    private struct ClosedTabSnapshot {
        let title: String
        let addressBarText: String
        let url: URL?
    }

    @Published private(set) var tabs: [TabState]
    @Published var selectedTabID: UUID? {
        didSet {
            updateSidebarAppearanceForSelection()
        }
    }
    @Published var sidebarAppearance: BrowserSidebarAppearance

    var shouldShowProgress: Bool {
        guard let tab = currentTab, tab.kind == .web else { return false }
        return tab.isLoading || tab.progress < 1
    }

    var progress: Double {
        currentTab?.progress ?? 0
    }

    var isLoading: Bool {
        currentTab?.isLoading ?? false
    }

    var canGoBack: Bool {
        currentTab?.canGoBack ?? false
    }

    var canGoForward: Bool {
        currentTab?.canGoForward ?? false
    }

    var currentURL: URL? {
        currentTab?.currentURL
    }

    var currentAddressText: String {
        currentTab?.addressBarText ?? ""
    }

    var currentTabExists: Bool {
        currentTab != nil
    }

    var hasMultipleTabs: Bool {
        tabs.count > 1
    }

    var canReopenLastClosedTab: Bool {
        !closedTabHistory.isEmpty
    }

    var isCurrentTabDisplayingWebContent: Bool {
        currentTab?.kind == .web
    }

    private let settings: BrowserSettings
    private var hasLoadedInitialPage = false
    private var webViews: [UUID: WKWebView]
    private var webViewToTabID: [ObjectIdentifier: UUID]
    private var progressObservations: [UUID: NSKeyValueObservation]
    private var pendingURLs: [UUID: URL]
    private var closedTabHistory: [ClosedTabSnapshot]
#if os(macOS)
    private var tabSidebarAppearances: [UUID: BrowserSidebarAppearance]
#endif

    init(settings: BrowserSettings) {
        self.settings = settings
        self.tabs = []
        self.sidebarAppearance = .default
        self.webViews = [:]
        self.webViewToTabID = [:]
        self.progressObservations = [:]
        self.pendingURLs = [:]
        self.closedTabHistory = []
#if os(macOS)
        self.tabSidebarAppearances = [:]
#endif
        super.init()
    }

    deinit {
        progressObservations.values.forEach { $0.invalidate() }
    }

    private func updateSidebarAppearanceForSelection() {
#if os(macOS)
        guard let tabID = selectedTabID else {
            sidebarAppearance = .default
            return
        }

        if let cachedAppearance = tabSidebarAppearances[tabID] {
            sidebarAppearance = cachedAppearance
        } else {
            sidebarAppearance = .default
            if let webView = webViews[tabID] {
                captureSidebarAppearance(from: webView, for: tabID)
            }
        }
#else
        sidebarAppearance = .default
#endif
    }

    func loadInitialPageIfNeeded() {
        guard !hasLoadedInitialPage else { return }
        hasLoadedInitialPage = true
        openNewTab(with: homeURL)
    }

    func openNewTab() {
        openNewTab(with: homeURL)
    }

    func openNewTab(with url: URL?) {
        let tabID = UUID()
        let isWebTab = url != nil
        let newTab = TabState(
            id: tabID,
            title: defaultTitle(for: isWebTab ? .web : .nativeHome),
            addressBarText: url?.absoluteString ?? "",
            canGoBack: false,
            canGoForward: false,
            isLoading: false,
            progress: 0,
            currentURL: url,
            kind: isWebTab ? .web : .nativeHome
        )

        tabs.append(newTab)
        selectedTabID = tabID
        if let url {
            pendingURLs[tabID] = url
            _ = makeConfiguredWebView(for: tabID)
            attemptToLoadPendingURL(for: tabID)
        }
    }

    func selectTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
    }

    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[index]
        recordClosedTab(for: id, tab: tab)
        tabs.remove(at: index)
        cleanupWebView(for: id)

        if selectedTabID == id {
            if index < tabs.endIndex {
                selectedTabID = tabs[index].id
            } else {
                selectedTabID = tabs.last?.id
            }
        }

        if tabs.isEmpty {
            openNewTab()
        }
    }

    func closeCurrentTab() {
        guard let id = selectedTabID else { return }
        closeTab(id)
    }

    func reopenLastClosedTab() {
        guard let snapshot = closedTabHistory.popLast() else { return }

        let tabID = UUID()
        let targetURL = snapshot.url ?? homeURL
        let kind: TabState.Kind = targetURL == nil ? .nativeHome : .web
        let addressText: String
        if let url = targetURL {
            addressText = snapshot.addressBarText.isEmpty ? url.absoluteString : snapshot.addressBarText
        } else {
            addressText = ""
        }
        let title: String
        if snapshot.title.isEmpty {
            title = defaultTitle(for: kind)
        } else {
            title = snapshot.title
        }

        let restoredTab = TabState(
            id: tabID,
            title: title,
            addressBarText: addressText,
            canGoBack: false,
            canGoForward: false,
            isLoading: false,
            progress: 0,
            currentURL: targetURL,
            kind: kind
        )

        tabs.append(restoredTab)
        selectedTabID = tabID
        if let url = targetURL {
            pendingURLs[tabID] = url
            _ = makeConfiguredWebView(for: tabID)
            attemptToLoadPendingURL(for: tabID)
        }
    }

    func selectNextTab() {
        guard hasMultipleTabs,
              let id = selectedTabID,
              let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let nextIndex = tabs.index(after: index)
        if nextIndex < tabs.endIndex {
            selectedTabID = tabs[nextIndex].id
        } else {
            selectedTabID = tabs.first?.id
        }
    }

    func selectPreviousTab() {
        guard hasMultipleTabs,
              let id = selectedTabID,
              let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        if index == tabs.startIndex {
            selectedTabID = tabs.last?.id
        } else {
            let previousIndex = tabs.index(before: index)
            selectedTabID = tabs[previousIndex].id
        }
    }

    func updateAddressText(_ text: String) {
        guard let id = selectedTabID,
              let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].addressBarText = text
    }

    func submitAddress() {
        guard let id = selectedTabID,
              let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let input = tabs[index].addressBarText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        let targetURL: URL
        if let url = BrowserViewModel.url(from: input) {
            targetURL = url
        } else {
            targetURL = settings.searchURL(for: input)
        }

        load(url: targetURL, in: id)
    }

    func load(url: URL, in tabID: UUID? = nil) {
        guard let id = tabID ?? selectedTabID,
              let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].kind = .web
        tabs[index].addressBarText = url.absoluteString
        tabs[index].progress = 0
        tabs[index].currentURL = url
        tabs[index].title = defaultTitle(for: .web)
        tabs[index].canGoBack = false
        tabs[index].canGoForward = false
        tabs[index].isLoading = true
        pendingURLs[id] = url
        _ = makeConfiguredWebView(for: id)
        attemptToLoadPendingURL(for: id)
    }

    func reloadCurrentTab() {
        guard let webView = currentWebView else { return }
        webView.reload()
    }

    func reloadOrStop() {
        guard let id = selectedTabID,
              let index = tabs.firstIndex(where: { $0.id == id }),
              let webView = webViews[id] else { return }
        if tabs[index].isLoading {
            webView.stopLoading()
        } else {
            webView.reload()
        }
    }

    func goBack() {
        guard let id = selectedTabID, let webView = webViews[id] else { return }
        webView.goBack()
    }

    func goForward() {
        guard let id = selectedTabID, let webView = webViews[id] else { return }
        webView.goForward()
    }

    func goHome() {
        guard let id = selectedTabID else { return }
        if let url = homeURL {
            load(url: url, in: id)
        } else {
            showNativeHome(in: id)
        }
    }

    func openInspector() {
        guard let id = selectedTabID, let webView = webViews[id] else { return }
#if os(macOS)
        webView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let inspectorSelectors = [
            "toggleInspector:",
            "_toggleInspector:",
            "showInspector:",
            "_showInspector:"
        ]

        for selectorName in inspectorSelectors {
            let selector = NSSelectorFromString(selectorName)
            if webView.responds(to: selector) {
                webView.perform(selector, with: nil)
                return
            }
        }

        webView.evaluateJavaScript("debugger;")
#else
        webView.evaluateJavaScript("debugger;")
#endif
    }

    func findInPage() {
        guard let webView = currentWebView else { return }
#if os(macOS)
        if webView.window?.firstResponder !== webView {
            webView.window?.makeFirstResponder(webView)
        }

        if webView.window == nil {
            _ = webView.becomeFirstResponder()
        }

        //webView.performTextFinderAction(.showFindInterface)
#endif
    }

    func zoomIn() {
#if os(macOS)
        adjustZoom(by: 0.1)
#endif
    }

    func zoomOut() {
#if os(macOS)
        adjustZoom(by: -0.1)
#endif
    }

    func resetZoom() {
#if os(macOS)
        guard let webView = currentWebView else { return }
        if webView.magnification != 1.0 {
            webView.setMagnification(1.0, centeredAt: CGPoint(x: webView.bounds.midX, y: webView.bounds.midY))
        }
#endif
    }

    private var currentTab: TabState? {
        guard let id = selectedTabID else { return nil }
        return tabs.first(where: { $0.id == id })
    }

    private var currentWebView: WKWebView? {
        guard let id = selectedTabID else { return nil }
        return webViews[id]
    }

    func isWebTab(_ id: UUID) -> Bool {
        tabs.first(where: { $0.id == id })?.kind == .web
    }

    private func showNativeHome(in id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].kind = .nativeHome
        tabs[index].title = defaultTitle(for: .nativeHome)
        tabs[index].addressBarText = ""
        tabs[index].canGoBack = false
        tabs[index].canGoForward = false
        tabs[index].isLoading = false
        tabs[index].progress = 0
        tabs[index].currentURL = nil
        pendingURLs.removeValue(forKey: id)
        cleanupWebView(for: id)
    }

    private func defaultTitle(for kind: TabState.Kind) -> String {
        switch kind {
        case .nativeHome:
            return "Hello"
        case .web:
            return "New Tab"
        }
    }

    private var homeURL: URL? { settings.homePageURL }

    func makeConfiguredWebView(for tabID: UUID) -> WKWebView {
        if let webView = webViews[tabID] {
            return webView
        }

        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
#if os(macOS)
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
#endif

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webViews[tabID] = webView
        configureWebView(webView, for: tabID)
        return webView
    }

    private func configureWebView(_ webView: WKWebView, for tabID: UUID) {
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webViewToTabID[ObjectIdentifier(webView)] = tabID

        progressObservations[tabID]?.invalidate()
        progressObservations[tabID] = webView.observe(\.estimatedProgress, options: .new) { [weak self] webView, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.updateProgress(for: webView, value: webView.estimatedProgress)
            }
        }

        attemptToLoadPendingURL(for: tabID)
    }

    private func attemptToLoadPendingURL(for tabID: UUID) {
        guard let url = pendingURLs.removeValue(forKey: tabID) else { return }
        let webView = makeConfiguredWebView(for: tabID)
        webView.load(URLRequest(url: url))
    }

    private func recordClosedTab(for tabID: UUID, tab: TabState) {
        let url: URL?
        if let webViewURL = webViews[tabID]?.url {
            url = webViewURL
        } else if let currentURL = tab.currentURL {
            url = currentURL
        } else {
            url = BrowserViewModel.url(from: tab.addressBarText)
        }

        let snapshot = ClosedTabSnapshot(
            title: tab.title,
            addressBarText: tab.addressBarText,
            url: url
        )

        closedTabHistory.append(snapshot)
        if closedTabHistory.count > 20 {
            closedTabHistory.removeFirst(closedTabHistory.count - 20)
        }
    }

    private func cleanupWebView(for tabID: UUID) {
        if let observation = progressObservations.removeValue(forKey: tabID) {
            observation.invalidate()
        }

        if let webView = webViews.removeValue(forKey: tabID) {
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            webViewToTabID.removeValue(forKey: ObjectIdentifier(webView))
        }

        pendingURLs.removeValue(forKey: tabID)
#if os(macOS)
        tabSidebarAppearances.removeValue(forKey: tabID)
        if selectedTabID == tabID {
            sidebarAppearance = .default
        }
#endif
    }

    private func tabID(for webView: WKWebView) -> UUID? {
        webViewToTabID[ObjectIdentifier(webView)]
    }

    private func updateProgress(for webView: WKWebView, value: Double) {
        guard let tabID = tabID(for: webView),
              let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index].progress = value
    }

#if os(macOS)
    private func adjustZoom(by delta: CGFloat) {
        guard let webView = currentWebView else { return }
        let newMagnification = max(0.5, min(3.0, webView.magnification + delta))
        webView.setMagnification(newMagnification, centeredAt: CGPoint(x: webView.bounds.midX, y: webView.bounds.midY))
    }

    private func captureSidebarAppearance(from webView: WKWebView, for tabID: UUID) {
        let script = """
        (() => {
            const transparentValues = new Set(['rgba(0, 0, 0, 0)', 'rgba(0,0,0,0)', 'transparent']);
            const resolveColor = (element) => {
                if (!element) { return null; }
                const color = window.getComputedStyle(element).backgroundColor;
                if (!color) { return null; }
                const normalized = color.trim().toLowerCase();
                if (transparentValues.has(normalized)) { return null; }
                return color;
            };
            return resolveColor(document.body) ?? resolveColor(document.documentElement) ?? null;
        })();
        """

        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self else { return }
            DispatchQueue.main.async {
                if let colorString = result as? String,
                   let nsColor = BrowserViewModel.nsColor(fromCSSColorString: colorString) {
                    let appearance = BrowserSidebarAppearance.make(from: nsColor)
                    self.storeSidebarAppearance(appearance, for: tabID)
                } else if error == nil {
                    self.storeSidebarAppearance(nil, for: tabID)
                }
            }
        }
    }

    private func storeSidebarAppearance(_ appearance: BrowserSidebarAppearance?, for tabID: UUID) {
        if let appearance {
            tabSidebarAppearances[tabID] = appearance
            if selectedTabID == tabID {
                sidebarAppearance = appearance
            }
        } else {
            tabSidebarAppearances.removeValue(forKey: tabID)
            if selectedTabID == tabID {
                sidebarAppearance = .default
            }
        }
    }

    private static func nsColor(fromCSSColorString css: String) -> NSColor? {
        let trimmed = css.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("rgb") else { return nil }

        let scanner = Scanner(string: trimmed)
        _ = scanner.scanUpToString("(")
        guard scanner.scanString("(") != nil else { return nil }

        var components: [CGFloat] = []
        let separators = CharacterSet(charactersIn: ",/ ")

        while !scanner.isAtEnd {
            if let value = scanner.scanDouble() {
                components.append(CGFloat(value))
            }

            if scanner.scanString(")") != nil {
                break
            }

            _ = scanner.scanCharacters(from: separators)
        }

        guard components.count >= 3 else { return nil }

        func normalize(_ value: CGFloat) -> CGFloat {
            if value > 1 {
                return max(0, min(1, value / 255.0))
            }
            return max(0, min(1, value))
        }

        let red = normalize(components[0])
        let green = normalize(components[1])
        let blue = normalize(components[2])
        let alpha = components.count >= 4 ? normalize(components[3]) : 1.0

        guard alpha > 0.05 else { return nil }

        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }
#endif
}

extension BrowserViewModel.TabState {
    var displayTitle: String {
        if !title.trimmingCharacters(in: .whitespaces).isEmpty {
            return title
        }
        switch kind {
        case .nativeHome:
            return "Hello"
        case .web:
            break
        }
        if let host = currentURL?.host, !host.isEmpty {
            return host
        }
        return "New Tab"
    }

    var displaySubtitle: String? {
        guard kind == .web else { return nil }
        guard let url = currentURL else { return nil }
        return url.absoluteString
    }
}

extension BrowserViewModel {
    static func url(from input: String) -> URL? {
        guard let url = URL(string: input) else { return nil }
        if url.scheme != nil {
            return url
        }

        if input.contains(" ") {
            return nil
        }

        let lowercased = input.lowercased()
        let looksLikeHost = lowercased.contains(".") || lowercased.contains(":") || lowercased.contains("localhost")
        guard looksLikeHost else { return nil }

        return URL(string: "https://\(input)")
    }
}

extension BrowserViewModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        updateNavigationState(for: webView, isLoading: true)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        updateNavigationState(for: webView, isLoading: true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateNavigationState(for: webView, isLoading: false)
        guard let tabID = tabID(for: webView),
              let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index].addressBarText = webView.url?.absoluteString ?? tabs[index].addressBarText
        tabs[index].currentURL = webView.url
        tabs[index].title = webView.title ?? tabs[index].title
#if os(macOS)
        captureSidebarAppearance(from: webView, for: tabID)
#endif
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        updateNavigationState(for: webView, isLoading: false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        updateNavigationState(for: webView, isLoading: false)
    }

    private func updateNavigationState(for webView: WKWebView, isLoading: Bool) {
        guard let tabID = tabID(for: webView),
              let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index].isLoading = isLoading
        tabs[index].canGoBack = webView.canGoBack
        tabs[index].canGoForward = webView.canGoForward
        tabs[index].currentURL = webView.url ?? tabs[index].currentURL
        if !isLoading {
            tabs[index].progress = 1
        }
    }
}

extension BrowserViewModel: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil, let url = navigationAction.request.url else {
            return nil
        }

        openNewTab(with: url)
        return nil
    }
}
