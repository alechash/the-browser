import SwiftUI
import WebKit
#if os(macOS)
import AppKit
#endif

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

        if viewModel.tabShowsWelcomeContent(tabID) {
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

        if viewModel.tabShowsWelcomeContent(tabID) {
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
