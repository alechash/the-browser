//
//  TheBrowserApp.swift
//  The Browser
//
//  Created by Jude Wilson on 11/8/25.
//

import SwiftUI
import WebKit

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

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Button(action: viewModel.goBack) {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .disabled(!viewModel.canGoBack)

                    Button(action: viewModel.goForward) {
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .disabled(!viewModel.canGoForward)

                    Button(action: viewModel.reloadOrStop) {
                        Image(systemName: viewModel.isLoading ? "xmark" : "arrow.clockwise")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .disabled(!viewModel.isLoading && !viewModel.canReload)
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .foregroundStyle(.secondary)

                    TextField("Search or enter website name", text: $viewModel.address, onCommit: viewModel.commitAddress)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        #endif

                    Button("Go", action: viewModel.commitAddress)
                        .buttonStyle(.borderedProminent)
                }

                if !viewModel.pageTitle.isEmpty {
                    Text(viewModel.pageTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                }

                if viewModel.isLoading {
                    ProgressView(value: viewModel.loadingProgress)
                        .progressViewStyle(.linear)
                }
            }
            .padding(12)
            .background(.thinMaterial)

            Divider()

            #if os(iOS)
            PlatformWebView(viewModel: viewModel)
                .ignoresSafeArea(edges: .bottom)
            #else
            PlatformWebView(viewModel: viewModel)
            #endif
        }
    }
}

final class BrowserViewModel: ObservableObject {
    @Published var address: String
    @Published var pageTitle: String = ""
    @Published var isLoading: Bool = false
    @Published var loadingProgress: Double = 0
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var canReload: Bool = true

    let webView: WKWebView
    private var progressObservation: NSKeyValueObservation?

    private let homeAddress = "https://apple.com"

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        #if os(iOS)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        #endif

        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.address = homeAddress

        webView.allowsBackForwardNavigationGestures = true

        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            self?.synchronizeState(with: webView, updateAddress: false)
        }

        commitAddress()
    }

    func commitAddress() {
        guard let url = normalizedURL(from: address) else {
            return
        }

        address = url.absoluteString
        webView.load(URLRequest(url: url))
        synchronizeState(with: webView, updateAddress: false)
    }

    func goBack() {
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }

    func reloadOrStop() {
        if isLoading {
            webView.stopLoading()
        } else if canReload {
            webView.reload()
        }
    }

    func synchronizeState(with webView: WKWebView, updateAddress: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.loadingProgress = webView.estimatedProgress
            self.isLoading = webView.isLoading
            self.canGoBack = webView.canGoBack
            self.canGoForward = webView.canGoForward
            self.canReload = webView.url != nil
            self.pageTitle = webView.title ?? ""

            if updateAddress, let url = webView.url {
                self.address = url.absoluteString
            }
        }
    }

    private func normalizedURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }

        if trimmed.contains(" ") || !trimmed.contains(".") {
            if let query = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                return URL(string: "https://duckduckgo.com/?q=\(query)")
            }
        }

        if let url = URL(string: "https://\(trimmed)") {
            return url
        }

        return nil
    }
}

final class BrowserCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    private let viewModel: BrowserViewModel

    init(viewModel: BrowserViewModel) {
        self.viewModel = viewModel
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        viewModel.synchronizeState(with: webView, updateAddress: false)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        viewModel.synchronizeState(with: webView, updateAddress: false)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        viewModel.synchronizeState(with: webView, updateAddress: true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        viewModel.synchronizeState(with: webView, updateAddress: true)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        viewModel.synchronizeState(with: webView, updateAddress: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

#if canImport(UIKit)
struct PlatformWebView: UIViewRepresentable {
    @ObservedObject var viewModel: BrowserViewModel

    func makeCoordinator() -> BrowserCoordinator {
        BrowserCoordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> WKWebView {
        viewModel.webView.navigationDelegate = context.coordinator
        viewModel.webView.uiDelegate = context.coordinator
        return viewModel.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#elseif canImport(AppKit)
struct PlatformWebView: NSViewRepresentable {
    @ObservedObject var viewModel: BrowserViewModel

    func makeCoordinator() -> BrowserCoordinator {
        BrowserCoordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> WKWebView {
        viewModel.webView.navigationDelegate = context.coordinator
        viewModel.webView.uiDelegate = context.coordinator
        return viewModel.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif
