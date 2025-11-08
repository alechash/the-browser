//
//  TheBrowserApp.swift
//  The Browser
//
//  Created by Jude Wilson on 11/8/25.
//

import SwiftUI
import WebKit
import Combine

#if os(iOS)
import UIKit
#else
import AppKit
#endif

@main
struct TheBrowserApp: App {
    var body: some Scene {
        WindowGroup {
            BrowserView()
        }
    }
}

struct BrowserView: View {
    @StateObject private var viewModel = BrowserViewModel()
    @FocusState private var isAddressFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 280)
                .background(Color.browserSidebarBackground)

            BrowserWebView(viewModel: viewModel)
                .background(Color.browserBackground)
        }
        .background(Color.browserBackground)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            viewModel.loadInitialPageIfNeeded()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            VStack(alignment: .leading, spacing: 12) {
                navigationControls
                addressField

                if viewModel.shouldShowProgress {
                    ProgressView(value: viewModel.progress)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Tabs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: viewModel.openNewTab) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .padding(6)
                            .background(Color.browserControlBackground)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.tabs) { tab in
                            TabRow(
                                tab: tab,
                                isSelected: tab.id == viewModel.selectedTabID,
                                selectAction: { viewModel.selectTab(tab.id) },
                                closeAction: { viewModel.closeTab(tab.id) }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                Button(action: viewModel.openInspector) {
                    Label("Web Inspector", systemImage: "ladybug")
                        .labelStyle(.leadingIcon)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.browserSidebarButtonBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.currentTabExists)
                .opacity(viewModel.currentTabExists ? 1 : 0.4)
            }
        }
        .padding(16)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(Color.browserAccent)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("The Browser")
                    .font(.headline)
                    .fontWeight(.semibold)
                Text("Workspace")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var navigationControls: some View {
        HStack(spacing: 8) {
            NavigationControlButton(
                symbol: "chevron.left",
                help: "Back",
                isEnabled: viewModel.canGoBack,
                action: viewModel.goBack
            )

            NavigationControlButton(
                symbol: "chevron.right",
                help: "Forward",
                isEnabled: viewModel.canGoForward,
                action: viewModel.goForward
            )

            NavigationControlButton(
                symbol: viewModel.isLoading ? "xmark" : "arrow.clockwise",
                help: viewModel.isLoading ? "Stop" : "Reload",
                isEnabled: viewModel.currentTabExists,
                action: viewModel.reloadOrStop
            )

            NavigationControlButton(
                symbol: "house",
                help: "Home",
                isEnabled: viewModel.currentTabExists,
                action: viewModel.goHome
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var addressField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Address")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(
                "Search or enter website name",
                text: Binding(
                    get: { viewModel.currentAddressText },
                    set: { viewModel.updateAddressText($0) }
                )
            )
            .focused($isAddressFocused)
            .textFieldStyle(.plain)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.browserControlBackground)
            )
            .onSubmit {
                viewModel.submitAddress()
                isAddressFocused = false
            }
#if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .disableAutocorrection(true)
            .submitLabel(.go)
#endif
        }
    }
}

private struct NavigationControlButton: View {
    let symbol: String
    let help: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.browserControlBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.browserControlBorder, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(Text(help))
        #if os(macOS)
        .help(help)
        #endif
    }
}

private struct TabRow: View {
    let tab: BrowserViewModel.TabState
    let isSelected: Bool
    let selectAction: () -> Void
    let closeAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.displayTitle)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                if let subtitle = tab.displaySubtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if tab.isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
            } else {
                Button(action: closeAction) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.primary)
                        .padding(6)
                        .background(Color.browserControlBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .opacity(0.7)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? Color.browserSidebarSelection : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: selectAction)
    }
}

private struct LeadingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon
            configuration.title
        }
    }
}

private extension LabelStyle where Self == LeadingIconLabelStyle {
    static var leadingIcon: LeadingIconLabelStyle { LeadingIconLabelStyle() }
}

@MainActor
final class BrowserViewModel: NSObject, ObservableObject {
    struct TabState: Identifiable, Equatable {
        let id: UUID
        var title: String
        var addressBarText: String
        var canGoBack: Bool
        var canGoForward: Bool
        var isLoading: Bool
        var progress: Double
        var currentURL: URL?
    }

    @Published private(set) var tabs: [TabState]
    @Published var selectedTabID: UUID?

    var shouldShowProgress: Bool {
        guard let tab = currentTab else { return false }
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

    private let homeURL: URL
    private var hasLoadedInitialPage = false
    private var webViews: [UUID: WKWebView]
    private var webViewToTabID: [ObjectIdentifier: UUID]
    private var progressObservations: [UUID: NSKeyValueObservation]
    private var pendingURLs: [UUID: URL]

    override init() {
        self.homeURL = URL(string: "https://www.apple.com")!
        self.tabs = []
        self.webViews = [:]
        self.webViewToTabID = [:]
        self.progressObservations = [:]
        self.pendingURLs = [:]
        super.init()
    }

    deinit {
        progressObservations.values.forEach { $0.invalidate() }
    }

    func loadInitialPageIfNeeded() {
        guard !hasLoadedInitialPage else { return }
        hasLoadedInitialPage = true
        openNewTab(with: homeURL)
    }

    func openNewTab() {
        openNewTab(with: homeURL)
    }

    func openNewTab(with url: URL) {
        let tabID = UUID()
        let newTab = TabState(
            id: tabID,
            title: "New Tab",
            addressBarText: url.absoluteString,
            canGoBack: false,
            canGoForward: false,
            isLoading: false,
            progress: 0,
            currentURL: nil
        )

        tabs.append(newTab)
        selectedTabID = tabID
        pendingURLs[tabID] = url
        _ = makeConfiguredWebView(for: tabID)
        attemptToLoadPendingURL(for: tabID)
    }

    func selectTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
    }

    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
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

    func updateAddressText(_ text: String) {
        guard let id = selectedTabID, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].addressBarText = text
    }

    func submitAddress() {
        guard let id = selectedTabID, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let input = tabs[index].addressBarText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        let targetURL: URL
        if let url = BrowserViewModel.url(from: input) {
            targetURL = url
        } else {
            targetURL = BrowserViewModel.searchURL(for: input)
        }

        load(url: targetURL, in: id)
    }

    func load(url: URL, in tabID: UUID? = nil) {
        guard let id = tabID ?? selectedTabID, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].addressBarText = url.absoluteString
        tabs[index].progress = 0
        tabs[index].currentURL = url
        pendingURLs[id] = url
        attemptToLoadPendingURL(for: id)
    }

    func reloadOrStop() {
        guard let id = selectedTabID, let index = tabs.firstIndex(where: { $0.id == id }), let webView = webViews[id] else { return }
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
        load(url: homeURL)
    }

    func presentShareSheet() {
        guard let url = currentURL else { return }

#if os(iOS)
        let activityController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController?
            .present(activityController, animated: true)
#endif
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

    private var currentTab: TabState? {
        guard let id = selectedTabID else { return nil }
        return tabs.first(where: { $0.id == id })
    }

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
    }

    private func tabID(for webView: WKWebView) -> UUID? {
        webViewToTabID[ObjectIdentifier(webView)]
    }

    private func updateProgress(for webView: WKWebView, value: Double) {
        guard let tabID = tabID(for: webView), let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index].progress = value
    }
}

private extension BrowserViewModel.TabState {
    var displayTitle: String {
        if !title.trimmingCharacters(in: .whitespaces).isEmpty {
            return title
        }
        if let host = currentURL?.host, !host.isEmpty {
            return host
        }
        return "New Tab"
    }

    var displaySubtitle: String? {
        guard let url = currentURL else { return nil }
        return url.absoluteString
    }
}

private extension BrowserViewModel {
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

    static func searchURL(for query: String) -> URL {
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url!
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
        guard let tabID = tabID(for: webView), let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index].addressBarText = webView.url?.absoluteString ?? tabs[index].addressBarText
        tabs[index].currentURL = webView.url
        tabs[index].title = webView.title ?? tabs[index].title
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        updateNavigationState(for: webView, isLoading: false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        updateNavigationState(for: webView, isLoading: false)
    }

    private func updateNavigationState(for webView: WKWebView, isLoading: Bool) {
        guard let tabID = tabID(for: webView), let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index].isLoading = isLoading
        tabs[index].canGoBack = webView.canGoBack
        tabs[index].canGoForward = webView.canGoForward
        tabs[index].currentURL = webView.url ?? tabs[index].currentURL
        if !isLoading {
            tabs[index].progress = 1
        }
    }
}

#if os(macOS)
struct BrowserWebView: NSViewRepresentable {
    @ObservedObject var viewModel: BrowserViewModel

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let tabID = viewModel.selectedTabID else {
            nsView.subviews.forEach { $0.removeFromSuperview() }
            return
        }

        let webView = viewModel.makeConfiguredWebView(for: tabID)

        if nsView.subviews.first != webView {
            nsView.subviews.forEach { $0.removeFromSuperview() }
            webView.translatesAutoresizingMaskIntoConstraints = false
            nsView.addSubview(webView)
            NSLayoutConstraint.activate([
                webView.leadingAnchor.constraint(equalTo: nsView.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: nsView.trailingAnchor),
                webView.topAnchor.constraint(equalTo: nsView.topAnchor),
                webView.bottomAnchor.constraint(equalTo: nsView.bottomAnchor)
            ])
        }
    }
}
#else
struct BrowserWebView: UIViewRepresentable {
    @ObservedObject var viewModel: BrowserViewModel

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let tabID = viewModel.selectedTabID else {
            uiView.subviews.forEach { $0.removeFromSuperview() }
            return
        }

        let webView = viewModel.makeConfiguredWebView(for: tabID)

        if uiView.subviews.first != webView {
            uiView.subviews.forEach { $0.removeFromSuperview() }
            webView.translatesAutoresizingMaskIntoConstraints = false
            uiView.addSubview(webView)
            NSLayoutConstraint.activate([
                webView.leadingAnchor.constraint(equalTo: uiView.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: uiView.trailingAnchor),
                webView.topAnchor.constraint(equalTo: uiView.topAnchor),
                webView.bottomAnchor.constraint(equalTo: uiView.bottomAnchor)
            ])
        }
    }
}
#endif

extension BrowserViewModel: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil, let url = navigationAction.request.url else {
            return nil
        }

        openNewTab(with: url)
        return nil
    }
}

private extension Color {
    static var browserBackground: Color {
#if os(macOS)
        Color(nsColor: .windowBackgroundColor)
#else
        Color(.systemBackground)
#endif
    }

    static var browserControlBackground: Color {
#if os(macOS)
        Color(nsColor: .underPageBackgroundColor)
#else
        Color(.secondarySystemBackground)
#endif
    }

    static var browserControlBorder: Color {
#if os(macOS)
        Color(nsColor: .separatorColor).opacity(0.25)
#else
        Color(.separator).opacity(0.25)
#endif
    }

    static var browserSidebarBackground: Color {
#if os(macOS)
        Color(nsColor: .controlBackgroundColor)
#else
        Color(.systemGroupedBackground)
#endif
    }

    static var browserSidebarButtonBackground: Color {
#if os(macOS)
        Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
#else
        Color(.tertiarySystemGroupedBackground)
#endif
    }

    static var browserSidebarSelection: Color {
        Color.blue.opacity(0.18)
    }

    static var browserAccent: Color {
        Color.blue
    }
}
