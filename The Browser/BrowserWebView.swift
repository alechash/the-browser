import SwiftUI
import WebKit
#if os(macOS)
import AppKit
#endif

#if os(macOS)
struct BrowserWebView: NSViewRepresentable {
    @ObservedObject var viewModel: BrowserViewModel
    let tabID: UUID?

    init(viewModel: BrowserViewModel, tabID: UUID? = nil) {
        self.viewModel = viewModel
        self.tabID = tabID
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let targetTabID = tabID ?? viewModel.selectedTabID

        guard let tabID = targetTabID else {
            nsView.subviews.forEach { $0.removeFromSuperview() }
            return
        }

        guard viewModel.isWebTab(tabID), !viewModel.isTabPoppedOut(tabID) else {
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
    let tabID: UUID?

    init(viewModel: BrowserViewModel, tabID: UUID? = nil) {
        self.viewModel = viewModel
        self.tabID = tabID
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let targetTabID = tabID ?? viewModel.selectedTabID

        guard let tabID = targetTabID else {
            uiView.subviews.forEach { $0.removeFromSuperview() }
            return
        }

        guard viewModel.isWebTab(tabID), !viewModel.isTabPoppedOut(tabID) else {
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
