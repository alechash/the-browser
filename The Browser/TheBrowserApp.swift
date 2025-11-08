
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

            Divider()
                .overlay(Color.black.opacity(0.08))

            ZStack {
                if let selectedTab = viewModel.selectedTab {
                    BrowserWebView(viewModel: selectedTab)
                        .background(Color.browserBackground)
                        .transition(.opacity)
                } else {
                    Color.browserBackground
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.browserBackground)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear { viewModel.loadInitialPageIfNeeded() }
    }

    @ViewBuilder
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            if viewModel.selectedTab != nil {
                addressBar
            }

            navigationSection

            Divider()
                .padding(.vertical, 4)
                .overlay(Color.white.opacity(0.08))

            tabsSection

            Spacer(minLength: 12)

            footerSection
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .frame(width: 320, maxHeight: .infinity, alignment: .top)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.sidebarBackground.opacity(0.98),
                    Color.sidebarBackground.opacity(0.9)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 20, x: 6, y: 0)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.sidebarAccent.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: "globe")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.sidebarAccent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("The Browser")
                    .font(.headline)
                    .fontWeight(.semibold)
                Text("A focused, elegant web experience")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var addressBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Address")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            TextField(
                "Search or enter website name",
                text: viewModel.bindingForAddressBarText(),
                onCommit: {
                    viewModel.submitAddress()
                    isAddressFocused = false
                }
            )
            .focused($isAddressFocused)
            .disableAutocorrection(true)
            .textFieldStyle(.plain)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.browserControlBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .submitLabel(.go)
            #endif

            if viewModel.shouldShowProgress {
                ProgressView(value: viewModel.progress)
                    .progressViewStyle(.linear)
                    .tint(Color.sidebarAccent)
            }
        }
    }

    private var navigationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Navigation")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            SidebarButton(
                symbol: "chevron.left",
                title: "Back",
                isEnabled: viewModel.canGoBack,
                action: viewModel.goBack
            )

            SidebarButton(
                symbol: "chevron.right",
                title: "Forward",
                isEnabled: viewModel.canGoForward,
                action: viewModel.goForward
            )

            SidebarButton(
                symbol: viewModel.reloadSymbol,
                title: viewModel.isLoading ? "Stop" : "Reload",
                isEnabled: viewModel.selectedTab != nil,
                action: viewModel.reloadOrStop
            )

            SidebarButton(
                symbol: "bookmark",
                title: "Home",
                isEnabled: viewModel.selectedTab != nil,
                action: viewModel.goHome
            )

            #if os(iOS)
            SidebarButton(
                symbol: "square.and.arrow.up",
                title: "Share",
                isEnabled: viewModel.canShare,
                action: viewModel.presentShareSheet
            )
            #endif
        }
    }

    private var tabsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tabs")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: viewModel.newTab) {
                    Label("New", systemImage: "plus")
                        .font(.caption)
                        .labelStyle(.titleAndIcon)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.sidebarAccent.opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.sidebarAccent.opacity(0.25), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.tabs) { tab in
                        TabRow(
                            tab: tab,
                            isSelected: viewModel.isSelected(tab)
                        ) {
                            viewModel.select(tab)
                        } closeAction: {
                            viewModel.close(tab)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var footerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.inspectorAvailable {
                SidebarButton(
                    symbol: "ladybug",
                    title: "Toggle Inspector",
                    isEnabled: true,
                    action: viewModel.toggleInspector
                )
            }

            Text("\(viewModel.tabs.count) tab\(viewModel.tabs.count == 1 ? "" : "s") open")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SidebarButton: View {
    let symbol: String
    let title: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.sidebarAccent.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.sidebarAccent)
                }

                Text(title)
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.browserControlBackground.opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(isEnabled ? 0.08 : 0.02), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

private struct TabRow: View {
    @ObservedObject var tab: BrowserTabViewModel
    let isSelected: Bool
    let selectAction: () -> Void
    let closeAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tab.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(isSelected ? .primary : .primary.opacity(0.9))
                    .lineLimit(1)

                Text(tab.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: closeAction) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.secondary.opacity(0.9))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close tab")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? Color.sidebarAccent.opacity(0.18) : Color.browserControlBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? Color.sidebarAccent.opacity(0.4) : Color.white.opacity(0.04), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: selectAction)
    }
}

@MainActor
final class BrowserViewModel: ObservableObject {
    @Published var tabs: [BrowserTabViewModel]
    @Published var selectedTabID: BrowserTabViewModel.ID

    init() {
        let initialTab = BrowserTabViewModel()
        self.tabs = [initialTab]
        self.selectedTabID = initialTab.id
    }

    var selectedTab: BrowserTabViewModel? {
        tabs.first { $0.id == selectedTabID }
    }

    var canGoBack: Bool {
        selectedTab?.canGoBack ?? false
    }

    var canGoForward: Bool {
        selectedTab?.canGoForward ?? false
    }

    var isLoading: Bool {
        selectedTab?.isLoading ?? false
    }

    var shouldShowProgress: Bool {
        selectedTab?.shouldShowProgress ?? false
    }

    var progress: Double {
        selectedTab?.progress ?? 0
    }

    var reloadSymbol: String {
        isLoading ? "xmark" : "arrow.clockwise"
    }

    var canShare: Bool {
        selectedTab?.currentURL != nil
    }

    var inspectorAvailable: Bool {
        selectedTab?.inspectorAvailable ?? false
    }

    func isSelected(_ tab: BrowserTabViewModel) -> Bool {
        selectedTabID == tab.id
    }

    func loadInitialPageIfNeeded() {
        selectedTab?.loadInitialPageIfNeeded()
    }

    func bindingForAddressBarText() -> Binding<String> {
        Binding(
            get: { self.selectedTab?.addressBarText ?? "" },
            set: { newValue in
                self.selectedTab?.addressBarText = newValue
            }
        )
    }

    func submitAddress() {
        selectedTab?.submitAddress()
    }

    func reloadOrStop() {
        selectedTab?.reloadOrStop()
    }

    func goBack() {
        selectedTab?.goBack()
    }

    func goForward() {
        selectedTab?.goForward()
    }

    func goHome() {
        selectedTab?.goHome()
    }

    func presentShareSheet() {
        selectedTab?.presentShareSheet()
    }

    func toggleInspector() {
        selectedTab?.toggleInspector()
    }

    func select(_ tab: BrowserTabViewModel) {
        selectedTabID = tab.id
    }

    func newTab() {
        let tab = BrowserTabViewModel()
        tabs.append(tab)
        selectedTabID = tab.id
        tab.loadInitialPageIfNeeded()
    }

    func close(_ tab: BrowserTabViewModel) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: index)

        if tabs.isEmpty {
            let freshTab = BrowserTabViewModel()
            tabs = [freshTab]
            selectedTabID = freshTab.id
            freshTab.loadInitialPageIfNeeded()
        } else if selectedTabID == tab.id {
            let newIndex = min(index, tabs.count - 1)
            selectedTabID = tabs[newIndex].id
        }
    }
}

@MainActor
final class BrowserTabViewModel: NSObject, ObservableObject, Identifiable {
    let id = UUID()

    @Published var addressBarText: String
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var progress: Double = 0
    @Published var currentURL: URL?
    @Published var pageTitle: String = "New Tab"

    private let homeURL: URL
    private var hasLoadedInitialPage = false
    private var pendingURLToLoad: URL?
    private var progressObservation: NSKeyValueObservation?
    private weak var webView: WKWebView?

    override init() {
        self.homeURL = URL(string: "https://www.apple.com")!
        self.addressBarText = homeURL.absoluteString
        self.currentURL = homeURL

        super.init()
    }

    deinit {
        progressObservation?.invalidate()
    }

    var shouldShowProgress: Bool {
        isLoading || progress < 1
    }

    var displayTitle: String {
        let trimmed = pageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if let host = currentURL?.host, !host.isEmpty {
            return host
        }
        return "New Tab"
    }

    var subtitle: String {
        currentURL?.absoluteString ?? addressBarText
    }

    #if os(macOS)
    var inspectorAvailable: Bool { true }
    #else
    var inspectorAvailable: Bool { false }
    #endif

    func loadInitialPageIfNeeded() {
        guard !hasLoadedInitialPage else { return }
        hasLoadedInitialPage = true
        load(url: homeURL)
    }

    func submitAddress() {
        let input = addressBarText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        let targetURL: URL
        if let url = BrowserTabViewModel.url(from: input) {
            targetURL = url
        } else {
            targetURL = BrowserTabViewModel.searchURL(for: input)
        }

        load(url: targetURL)
    }

    func load(url: URL) {
        addressBarText = url.absoluteString
        progress = 0
        currentURL = url
        pageTitle = url.host ?? "New Tab"
        pendingURLToLoad = url
        attemptToLoadPendingURL()
    }

    func reloadOrStop() {
        guard let webView else { return }
        if isLoading {
            webView.stopLoading()
        } else {
            webView.reload()
        }
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
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

    func toggleInspector() {
        #if os(macOS)
        guard let webView else { return }
        if webView.responds(to: NSSelectorFromString("toggleInspector:")) {
            webView.perform(NSSelectorFromString("toggleInspector:"))
        }
        #endif
    }
}

private extension BrowserTabViewModel {
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

extension BrowserTabViewModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        updateNavigationState(isLoading: true)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        updateNavigationState(isLoading: true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateNavigationState(isLoading: false)
        addressBarText = webView.url?.absoluteString ?? addressBarText
        pageTitle = webView.title ?? pageTitle
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        updateNavigationState(isLoading: false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        updateNavigationState(isLoading: false)
    }

    private func updateNavigationState(isLoading: Bool) {
        self.isLoading = isLoading
        if let webView {
            canGoBack = webView.canGoBack
            canGoForward = webView.canGoForward
            currentURL = webView.url ?? currentURL
        }
        if !isLoading {
            progress = 1
        }
    }
}

#if os(macOS)
struct BrowserWebView: NSViewRepresentable {
    @ObservedObject var viewModel: BrowserTabViewModel

    func makeNSView(context: Context) -> WKWebView {
        viewModel.makeConfiguredWebView()
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#else
struct BrowserWebView: UIViewRepresentable {
    @ObservedObject var viewModel: BrowserTabViewModel

    func makeUIView(context: Context) -> WKWebView {
        viewModel.makeConfiguredWebView()
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif

extension BrowserTabViewModel {
    func makeConfiguredWebView() -> WKWebView {
        if let webView {
            return webView
        }

        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        #if os(macOS)
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif

        let webView = WKWebView(frame: .zero, configuration: configuration)
        configureWebView(webView)
        return webView
    }

    private func configureWebView(_ webView: WKWebView) {
        self.webView = webView
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true

        progressObservation?.invalidate()
        progressObservation = webView.observe(\.estimatedProgress, options: .new) { [weak self] webView, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.progress = webView.estimatedProgress
            }
        }

        attemptToLoadPendingURL()
    }

    private func attemptToLoadPendingURL() {
        guard let webView, let url = pendingURLToLoad else { return }
        pendingURLToLoad = nil
        webView.load(URLRequest(url: url))
    }
}

extension BrowserTabViewModel: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil, let url = navigationAction.request.url else {
            return nil
        }

        load(url: url)
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

    static var sidebarBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(.systemGroupedBackground)
        #endif
    }

    static var sidebarAccent: Color {
        #if os(macOS)
        Color(nsColor: .controlAccentColor)
        #else
        Color(.systemBlue)
        #endif
    }
}
