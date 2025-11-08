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
        WindowGroup(id: "browser") {
            BrowserView()
        }
#if os(macOS)
        .commands {
            BrowserCommands()
        }
#endif
    }
}

struct BrowserView: View {
    @StateObject private var settings: BrowserSettings
    @StateObject private var viewModel: BrowserViewModel
    @FocusState private var isAddressFocused: Bool
    @State private var isShowingSettings = false
    @State private var isWebContentFullscreen = false

    private let sidebarWidth: CGFloat = 280

    init() {
        let settings = BrowserSettings()
        _settings = StateObject(wrappedValue: settings)
        _viewModel = StateObject(wrappedValue: BrowserViewModel(settings: settings))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            BrowserWebView(viewModel: viewModel)
                .background(Color.browserBackground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.leading, isWebContentFullscreen ? 0 : sidebarWidth)
                .animation(.easeInOut(duration: 0.22), value: isWebContentFullscreen)

            if !isWebContentFullscreen {
                sidebar
                    .frame(width: sidebarWidth)
                    .background(viewModel.sidebarBackgroundColor)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            if isWebContentFullscreen {
                VStack {
                    HStack {
                        NavigationControlButton(
                            symbol: "sidebar.leading",
                            help: "Show Sidebar",
                            isEnabled: true,
                            action: { withAnimation { isWebContentFullscreen = false } }
                        )
                        Spacer()
                    }
                    Spacer()
                }
                .padding(24)
            }
        }
        .background(Color.browserBackground)
#if os(macOS)
        .background(MacWindowConfigurator())
#endif
        .frame(maxWidth: .infinity, maxHeight: .infinity)
#if os(macOS)
        .ignoresSafeArea()
#else
        .ignoresSafeArea(.keyboard, edges: .bottom)
#endif
        .onAppear {
            viewModel.loadInitialPageIfNeeded()
        }
#if os(macOS)
        .focusedSceneValue(\.browserActions, commandContext)
#endif
        .sheet(isPresented: $isShowingSettings) {
            SettingsPanel(settings: settings)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            VStack(alignment: .leading, spacing: 12) {
                navigationControls
                addressField
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

                Button(action: { isShowingSettings = true }) {
                    Label("Settings", systemImage: "gearshape")
                        .labelStyle(.leadingIcon)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.browserSidebarButtonBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }

#if os(macOS)
    private var commandContext: BrowserCommandContext {
        BrowserCommandContext(
            openNewTab: viewModel.openNewTab,
            closeCurrentTab: viewModel.closeCurrentTab,
            reopenLastClosedTab: viewModel.reopenLastClosedTab,
            selectNextTab: viewModel.selectNextTab,
            selectPreviousTab: viewModel.selectPreviousTab,
            reload: viewModel.reloadCurrentTab,
            focusAddressBar: {
                if isWebContentFullscreen {
                    withAnimation {
                        isWebContentFullscreen = false
                    }
                }
                isAddressFocused = true
            },
            findOnPage: viewModel.findInPage,
            zoomIn: viewModel.zoomIn,
            zoomOut: viewModel.zoomOut,
            resetZoom: viewModel.resetZoom,
            toggleContentFullscreen: {
                withAnimation {
                    isWebContentFullscreen.toggle()
                }
            },
            canSelectNextTab: viewModel.hasMultipleTabs,
            canSelectPreviousTab: viewModel.hasMultipleTabs,
            canReopenLastClosedTab: viewModel.canReopenLastClosedTab,
            hasActiveTab: viewModel.currentTabExists
        )
    }
#endif

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
#if os(macOS)
            WindowControls()
#endif

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

            NavigationControlButton(
                symbol: "arrow.up.left.and.arrow.down.right",
                help: "Enter Fullscreen",
                isEnabled: viewModel.currentTabExists,
                action: { withAnimation { isWebContentFullscreen = true } }
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
            .overlay(alignment: .bottomLeading) {
                if viewModel.shouldShowProgress {
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.browserAccent)
                            .frame(
                                width: geometry.size.width * max(viewModel.progress, 0),
                                height: 3
                            )
                    }
                    .frame(height: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
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

#if os(macOS)
private struct BrowserCommandContext {
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

private extension FocusedValues {
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

#if os(macOS)
private struct WindowControls: View {
    var body: some View {
        HStack(spacing: 8) {
            WindowControlButton(role: .close)
            WindowControlButton(role: .minimize)
            WindowControlButton(role: .zoom)
        }
    }
}

private struct WindowControlButton: View {
    enum Role {
        case close
        case minimize
        case zoom

        var color: Color {
            switch self {
            case .close:
                return Color(red: 1.0, green: 0.36, blue: 0.35)
            case .minimize:
                return Color(red: 1.0, green: 0.8, blue: 0.22)
            case .zoom:
                return Color(red: 0.4, green: 0.85, blue: 0.38)
            }
        }
    }

    let role: Role

    var body: some View {
        Button(action: performAction) {
            Circle()
                .fill(role.color)
                .frame(width: 14, height: 14)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.12), lineWidth: 0.5)
                )
                .accessibilityLabel(Text(accessibilityLabel))
        }
        .buttonStyle(.plain)
    }

    private var accessibilityLabel: String {
        switch role {
        case .close: return "Close window"
        case .minimize: return "Minimize window"
        case .zoom: return "Zoom window"
        }
    }

    private func performAction() {
        guard let window = NSApp.keyWindow else { return }
        switch role {
        case .close:
            window.performClose(nil)
        case .minimize:
            window.miniaturize(nil)
        case .zoom:
            window.zoom(nil)
        }
    }
}

private struct MacWindowConfigurator: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        configureIfPossible(view, context: context)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configureIfPossible(nsView, context: context)
    }

    private func configureIfPossible(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.configure(window: window)
        }
    }

    final class Coordinator {
        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []

        deinit {
            removeObservers()
        }

        func configure(window: NSWindow) {
            applyConfiguration(to: window)

            if self.window !== window {
                removeObservers()
                self.window = window

                let notificationNames: [Notification.Name] = [
                    NSWindow.didBecomeKeyNotification,
                    NSWindow.didDeminiaturizeNotification,
                    NSWindow.didExitFullScreenNotification,
                    NSWindow.didResizeNotification
                ]

                observers = notificationNames.map { name in
                    NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        guard let self, let window = self.window else { return }
                        self.applyConfiguration(to: window)
                    }
                }
            }
        }

        private func applyConfiguration(to window: NSWindow) {
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isMovableByWindowBackground = true
        }

        private func removeObservers() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
        }
    }
}
#endif

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

final class BrowserSettings: ObservableObject {
    enum SearchEngine: String, CaseIterable, Identifiable {
        case google
        case duckDuckGo
        case bing

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .google:
                return "Google"
            case .duckDuckGo:
                return "DuckDuckGo"
            case .bing:
                return "Bing"
            }
        }

        fileprivate func searchURL(for query: String) -> URL {
            let base: String
            switch self {
            case .google:
                base = "https://www.google.com/search"
            case .duckDuckGo:
                base = "https://duckduckgo.com/"
            case .bing:
                base = "https://www.bing.com/search"
            }

            var components = URLComponents(string: base)!
            components.queryItems = [URLQueryItem(name: "q", value: query)]
            return components.url ?? URL(string: base)!
        }
    }

    @Published var defaultSearchEngine: SearchEngine {
        didSet {
            userDefaults.set(defaultSearchEngine.rawValue, forKey: Keys.searchEngine)
        }
    }

    @Published var homePage: String {
        didSet {
            userDefaults.set(homePage, forKey: Keys.homePage)
        }
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        if let rawValue = userDefaults.string(forKey: Keys.searchEngine),
           let storedEngine = SearchEngine(rawValue: rawValue) {
            defaultSearchEngine = storedEngine
        } else {
            defaultSearchEngine = .google
        }

        if let storedHome = userDefaults.string(forKey: Keys.homePage), !storedHome.isEmpty {
            homePage = storedHome
        } else {
            homePage = BrowserSettings.fallbackHomePage
        }
    }

    var homePageURL: URL {
        BrowserSettings.normalizedHomePageURL(from: homePage) ?? URL(string: BrowserSettings.fallbackHomePage)!
    }

    func searchURL(for query: String) -> URL {
        defaultSearchEngine.searchURL(for: query)
    }

    @discardableResult
    func applyHomePageInput(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        guard let url = BrowserSettings.normalizedHomePageURL(from: trimmed) else {
            return false
        }

        homePage = url.absoluteString
        return true
    }

    private static func normalizedHomePageURL(from input: String) -> URL? {
        if let directURL = URL(string: input), let scheme = directURL.scheme, !scheme.isEmpty {
            return directURL
        }

        if let hostURL = BrowserSettings.makeHostURL(from: input) {
            return hostURL
        }

        return nil
    }

    private static func makeHostURL(from input: String) -> URL? {
        if input.contains(" ") { return nil }

        let lowercased = input.lowercased()
        let looksLikeHost = lowercased.contains(".") || lowercased.contains(":") || lowercased.contains("localhost")
        guard looksLikeHost else { return nil }

        return URL(string: "https://\(input)")
    }

    private enum Keys {
        static let searchEngine = "BrowserSettings.searchEngine"
        static let homePage = "BrowserSettings.homePage"
    }

    private static let fallbackHomePage = "https://www.apple.com"
}

struct SettingsPanel: View {
    @ObservedObject var settings: BrowserSettings
    @Environment(\.dismiss) private var dismiss
    @State private var homePageDraft: String
    @State private var validationMessage: String?

    init(settings: BrowserSettings) {
        self.settings = settings
        _homePageDraft = State(initialValue: settings.homePage)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Default Search Engine") {
                    Picker("Search Engine", selection: $settings.defaultSearchEngine) {
                        ForEach(BrowserSettings.SearchEngine.allCases) { engine in
                            Text(engine.displayName).tag(engine)
                        }
                    }
#if os(iOS)
                    .pickerStyle(.segmented)
#endif
                }

                Section("Home Page") {
                    TextField("Home page URL", text: $homePageDraft)
#if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .disableAutocorrection(true)
#endif
                        .onSubmit(saveHomePage)

                    if let validationMessage {
                        Text(validationMessage)
                            .font(.footnote)
                            .foregroundStyle(Color.red)
                    }

                    Button("Save Home Page", action: saveHomePage)
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                }
            }
            .frame(minWidth: 360, minHeight: 260)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func saveHomePage() {
        if settings.applyHomePageInput(homePageDraft) {
            validationMessage = nil
            homePageDraft = settings.homePage
        } else {
            validationMessage = "Enter a valid URL or host name."
        }
    }
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

    private struct ClosedTabSnapshot {
        let title: String
        let addressBarText: String
        let url: URL?
    }

    @Published private(set) var tabs: [TabState]
    @Published var selectedTabID: UUID? {
        didSet {
            updateSidebarBackgroundForSelection()
        }
    }
    @Published var sidebarBackgroundColor: Color

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

    var hasMultipleTabs: Bool {
        tabs.count > 1
    }

    var canReopenLastClosedTab: Bool {
        !closedTabHistory.isEmpty
    }

    private let settings: BrowserSettings
    private var hasLoadedInitialPage = false
    private var webViews: [UUID: WKWebView]
    private var webViewToTabID: [ObjectIdentifier: UUID]
    private var progressObservations: [UUID: NSKeyValueObservation]
    private var pendingURLs: [UUID: URL]
    private var closedTabHistory: [ClosedTabSnapshot]
#if os(macOS)
    private var tabSidebarColors: [UUID: Color]
#endif

    init(settings: BrowserSettings) {
        self.settings = settings
        self.tabs = []
        self.sidebarBackgroundColor = Color.browserSidebarBackground
        self.webViews = [:]
        self.webViewToTabID = [:]
        self.progressObservations = [:]
        self.pendingURLs = [:]
        self.closedTabHistory = []
#if os(macOS)
        self.tabSidebarColors = [:]
#endif
        super.init()
    }

    deinit {
        progressObservations.values.forEach { $0.invalidate() }
    }

    private func updateSidebarBackgroundForSelection() {
#if os(macOS)
        guard let tabID = selectedTabID else {
            sidebarBackgroundColor = Color.browserSidebarBackground
            return
        }

        if let cachedColor = tabSidebarColors[tabID] {
            sidebarBackgroundColor = cachedColor
        } else {
            sidebarBackgroundColor = Color.browserSidebarBackground
            if let webView = webViews[tabID] {
                captureSidebarBackgroundColor(from: webView, for: tabID)
            }
        }
#else
        sidebarBackgroundColor = Color.browserSidebarBackground
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
        pendingURLs[tabID] = url
        _ = makeConfiguredWebView(for: tabID)
        selectedTabID = tabID
        attemptToLoadPendingURL(for: tabID)
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
        let addressText = snapshot.addressBarText.isEmpty ? targetURL.absoluteString : snapshot.addressBarText
        let title = snapshot.title.isEmpty ? "New Tab" : snapshot.title

        let restoredTab = TabState(
            id: tabID,
            title: title,
            addressBarText: addressText,
            canGoBack: false,
            canGoForward: false,
            isLoading: false,
            progress: 0,
            currentURL: snapshot.url
        )

        tabs.append(restoredTab)
        pendingURLs[tabID] = targetURL
        _ = makeConfiguredWebView(for: tabID)
        selectedTabID = tabID
        attemptToLoadPendingURL(for: tabID)
    }

    func selectNextTab() {
        guard hasMultipleTabs, let id = selectedTabID, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let nextIndex = tabs.index(after: index)
        if nextIndex < tabs.endIndex {
            selectedTabID = tabs[nextIndex].id
        } else {
            selectedTabID = tabs.first?.id
        }
    }

    func selectPreviousTab() {
        guard hasMultipleTabs, let id = selectedTabID, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        if index == tabs.startIndex {
            selectedTabID = tabs.last?.id
        } else {
            let previousIndex = tabs.index(before: index)
            selectedTabID = tabs[previousIndex].id
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
            targetURL = settings.searchURL(for: input)
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

    func reloadCurrentTab() {
        guard let webView = currentWebView else { return }
        webView.reload()
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

    func findInPage() {
        guard let webView = currentWebView else { return }
#if os(macOS)
        if webView.window?.firstResponder !== webView {
            webView.window?.makeFirstResponder(webView)
        }

        if webView.window == nil {
            _ = webView.becomeFirstResponder()
        }

        webView.performTextFinderAction(.showFindInterface)
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

    private var homeURL: URL { settings.homePageURL }

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
        tabSidebarColors.removeValue(forKey: tabID)
        if selectedTabID == tabID {
            sidebarBackgroundColor = Color.browserSidebarBackground
        }
#endif
    }

    private func tabID(for webView: WKWebView) -> UUID? {
        webViewToTabID[ObjectIdentifier(webView)]
    }

    private func updateProgress(for webView: WKWebView, value: Double) {
        guard let tabID = tabID(for: webView), let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index].progress = value
    }

#if os(macOS)
    private func adjustZoom(by delta: CGFloat) {
        guard let webView = currentWebView else { return }
        let newMagnification = max(0.5, min(3.0, webView.magnification + delta))
        webView.setMagnification(newMagnification, centeredAt: CGPoint(x: webView.bounds.midX, y: webView.bounds.midY))
    }

    private func captureSidebarBackgroundColor(from webView: WKWebView, for tabID: UUID) {
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
                    let tinted = BrowserViewModel.makeSidebarTint(from: nsColor)
                    let swiftUIColor = Color(nsColor: tinted)
                    self.storeSidebarColor(swiftUIColor, for: tabID)
                } else if error == nil {
                    self.storeSidebarColor(nil, for: tabID)
                }
            }
        }
    }

    private func storeSidebarColor(_ color: Color?, for tabID: UUID) {
        if let color {
            tabSidebarColors[tabID] = color
            if selectedTabID == tabID {
                sidebarBackgroundColor = color
            }
        } else {
            tabSidebarColors.removeValue(forKey: tabID)
            if selectedTabID == tabID {
                sidebarBackgroundColor = Color.browserSidebarBackground
            }
        }
    }

    private static func makeSidebarTint(from color: NSColor) -> NSColor {
        let source = color.usingColorSpace(.deviceRGB) ?? color
        let windowColor = NSColor.windowBackgroundColor.usingColorSpace(.deviceRGB) ?? NSColor.windowBackgroundColor
        return source.blended(withFraction: 0.7, of: windowColor) ?? windowColor
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
#if os(macOS)
        captureSidebarBackgroundColor(from: webView, for: tabID)
#endif
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
        Color(nsColor: NSColor.windowBackgroundColor)
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
