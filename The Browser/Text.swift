//
//  TheBrowserApp.swift
//  The Browser
//
//  Created by Jude Wilson on 11/8/25.
//

import SwiftUI
import WebKit
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
        VStack(spacing: 0) {
            addressBar
            BrowserWebView(webView: viewModel.webView)
                .background(Color.browserBackground)
            toolbar
        }
        .background(Color.browserBackground)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            viewModel.loadInitialPageIfNeeded()
        }
    }

    private var addressBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "safari")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.blue)

                    TextField("Search or enter website name",
                              text: $viewModel.addressBarText,
                              onCommit: {
                        viewModel.submitAddress()
                        isAddressFocused = false
                    })
                    .focused($isAddressFocused)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
                    .submitLabel(.go)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.browserControlBackground)
                )

                Button(action: viewModel.reloadOrStop) {
                    Image(systemName: viewModel.isLoading ? "xmark" : "arrow.clockwise")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(Color.browserControlBackground)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if viewModel.shouldShowProgress {
                ProgressView(value: viewModel.progress)
                    .progressViewStyle(.linear)
                    .tint(.blue)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .background(.regularMaterial)
    }

    private var toolbar: some View {
        HStack(spacing: 32) {
            ToolbarButton(symbol: "chevron.left", title: "Back") {
                viewModel.goBack()
            }
            .disabled(!viewModel.canGoBack)

            ToolbarButton(symbol: "chevron.right", title: "Forward") {
                viewModel.goForward()
            }
            .disabled(!viewModel.canGoForward)

#if os(iOS)
            ToolbarButton(symbol: "square.and.arrow.up", title: "Share") {
                viewModel.presentShareSheet()
            }
            .disabled(viewModel.currentURL == nil)
#endif
            ToolbarButton(symbol: "bookmark", title: "Home") {
                viewModel.goHome()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }
}

private struct ToolbarButton: View {
    let symbol: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                Text(title)
                    .font(.caption2)
            }
            .frame(minWidth: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}

@MainActor
final class BrowserViewModel: NSObject, ObservableObject {
    @Published var addressBarText: String
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var progress: Double = 0
    @Published var currentURL: URL?

    let webView: WKWebView

    private let homeURL: URL
    private var hasLoadedInitialPage = false
    private var progressObservation: NSKeyValueObservation?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.homeURL = URL(string: "https://www.apple.com")!
        self.addressBarText = homeURL.absoluteString
        self.currentURL = homeURL

        super.init()

        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true

        progressObservation = webView.observe(\.estimatedProgress, options: .new) { [weak self] webView, _ in
            guard let self else { return }
            Task { @MainActor in
                progress = webView.estimatedProgress
            }
        }
    }

    deinit {
        progressObservation?.invalidate()
    }

    var shouldShowProgress: Bool {
        isLoading || progress < 1
    }

    func loadInitialPageIfNeeded() {
        guard !hasLoadedInitialPage else { return }
        hasLoadedInitialPage = true
        load(url: homeURL)
    }

    func submitAddress() {
        let input = addressBarText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        let targetURL: URL
        if let url = BrowserViewModel.url(from: input) {
            targetURL = url
        } else {
            targetURL = BrowserViewModel.searchURL(for: input)
        }

        load(url: targetURL)
    }

    func load(url: URL) {
        addressBarText = url.absoluteString
        progress = 0
        currentURL = url
        webView.load(URLRequest(url: url))
    }

    func reloadOrStop() {
        if isLoading {
            webView.stopLoading()
        } else {
            webView.reload()
        }
    }

    func goBack() {
        webView.goBack()
    }

    func goForward() {
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
        updateNavigationState(isLoading: true)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        updateNavigationState(isLoading: true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateNavigationState(isLoading: false)
        addressBarText = webView.url?.absoluteString ?? addressBarText
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        updateNavigationState(isLoading: false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        updateNavigationState(isLoading: false)
    }

    private func updateNavigationState(isLoading: Bool) {
        self.isLoading = isLoading
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        currentURL = webView.url ?? currentURL
        if !isLoading {
            progress = 1
        }
    }
}

#if os(macOS)
struct BrowserWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#else
struct BrowserWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif

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
}
