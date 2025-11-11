import SwiftUI
import WebKit
import Combine
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

@MainActor
final class BrowserViewModel: NSObject, ObservableObject {
    struct TabState: Identifiable, Equatable {
        enum Kind: Equatable {
            case nativeHome
            case history
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

    struct DownloadItem: Identifiable, Equatable {
        enum State: Equatable {
            case preparing
            case downloading(progress: Double?)
            case finished(URL)
            case failed(String)
        }

        let id: UUID
        var filename: String
        var state: State
        var sourceURL: URL?
    }

    struct HistoryEntry: Identifiable, Codable, Equatable {
        let id: UUID
        var url: URL
        var title: String
        var lastVisited: Date
        var visitCount: Int
        var normalizedURL: String

        var displayTitle: String {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? url.absoluteString : trimmed
        }

        var displayURL: String {
            url.absoluteString
        }
    }

    struct Workspace: Identifiable, Equatable {
        struct PinnedTab: Identifiable, Equatable {
            let id: UUID
            var title: String
            var url: URL?
            var capturedAt: Date

            var displayURL: String {
                url?.absoluteString ?? ""
            }
        }

        struct SavedTab: Identifiable, Equatable {
            let id: UUID
            var title: String
            var url: URL?
            var capturedAt: Date

            var displayURL: String {
                url?.absoluteString ?? ""
            }
        }

        struct Note: Identifiable, Equatable {
            let id: UUID
            var text: String
            var createdAt: Date
        }

        struct Link: Identifiable, Equatable {
            let id: UUID
            var title: String
            var url: URL?
            var createdAt: Date

            var displayTitle: String {
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
                return url?.absoluteString ?? "Untitled Link"
            }
        }

        struct ImageResource: Identifiable, Equatable {
            let id: UUID
            var url: URL?
            var caption: String
            var createdAt: Date

            var displayCaption: String {
                caption.isEmpty ? "Saved Image" : caption
            }
        }

        let id: UUID
        var name: String
        var iconName: String
        var colorHex: String
        var createdAt: Date
        var pinnedTabs: [PinnedTab]
        var savedTabs: [SavedTab]
        var notes: [Note]
        var links: [Link]
        var images: [ImageResource]

        var isEmpty: Bool {
            pinnedTabs.isEmpty && savedTabs.isEmpty && notes.isEmpty && links.isEmpty && images.isEmpty
        }

        var accentColor: Color {
            Color.fromHex(colorHex) ?? .browserAccent
        }
    }

    enum SplitOrientation: Equatable {
        case horizontal
        case vertical
    }

    private struct ClosedTabSnapshot {
        let title: String
        let addressBarText: String
        let url: URL?
        let kind: TabState.Kind
    }

    private struct PersistedTab: Codable {
        enum Kind: String, Codable {
            case nativeHome
            case history
            case web
        }

        let kind: Kind
        let url: String?
    }

    private struct PersistedSession: Codable {
        let tabs: [PersistedTab]
        let selectedIndex: Int?
    }

    @Published private(set) var tabs: [TabState] {
        didSet { persistSessionIfNeeded() }
    }
    @Published var selectedTabID: UUID? {
        didSet {
            sanitizeSplitViewTabs()
#if os(macOS)
            if let selectedTabID, isTabPoppedOut(selectedTabID) {
                restoreTabFromPopOut(selectedTabID)
            }
#endif
            updateSidebarAppearanceForSelection()
            persistSessionIfNeeded()
            clearAddressSuggestions()
            if selectedTabID != nil {
                selectedWorkspaceID = nil
            }
        }
    }
    @Published var selectedWorkspaceID: UUID? {
        didSet {
            if selectedWorkspaceID != nil {
                if selectedTabID != nil {
                    selectedTabID = nil
                } else {
                    updateSidebarAppearanceForSelection()
                }
                sidebarAppearance = .default
            }
        }
    }
    @Published var sidebarAppearance: BrowserSidebarAppearance
    @Published private(set) var splitViewTabIDs: [UUID]
    @Published var splitViewOrientation: SplitOrientation
#if os(macOS)
    @Published private(set) var poppedOutTabIDs: Set<UUID>
#endif
    @Published private var splitViewFractions: [UUID: CGFloat]
    @Published private(set) var downloads: [DownloadItem]
    @Published private(set) var history: [HistoryEntry]
    @Published private(set) var addressSuggestions: [HistoryEntry]
    @Published private(set) var isShowingAddressSuggestions: Bool
    @Published private(set) var highlightedAddressSuggestionID: UUID?
    @Published private(set) var workspaces: [Workspace]

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

    var currentTabTitle: String {
        currentTab?.displayTitle ?? ""
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

    var currentTabKind: TabState.Kind? {
        currentTab?.kind
    }

    var activeWebViewTabIDs: [UUID] {
        guard selectedWorkspaceID == nil else { return [] }
        let identifiers = computeActiveWebViewTabIDs()
        ensureSplitFractions(for: identifiers)
        return identifiers
    }

    var currentWorkspaceID: UUID? {
        selectedWorkspaceID
    }

    var currentWorkspace: Workspace? {
        guard let id = selectedWorkspaceID else { return nil }
        return workspace(with: id)
    }

    func faviconURL(for tab: TabState) -> URL? {
        guard tab.kind == .web else { return nil }
        guard let targetURL = resolvedURL(for: tab.id, tab: tab) ?? tab.currentURL else {
            return nil
        }
        guard let host = targetURL.host else { return nil }

        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let encodedHost = host.addingPercentEncoding(withAllowedCharacters: allowed) ?? host
        return URL(string: "https://www.google.com/s2/favicons?domain=\(encodedHost)&sz=64")
    }

    private let settings: BrowserSettings
    private let sessionDefaults: UserDefaults
    private static let sessionStorageKey = "browser.session.state"
    private static let historyStorageKey = "browser.history.entries"
    private static let historyLimit = 500
    private static let workspaceIconPool = [
        "sparkles",
        "paintpalette",
        "lightbulb",
        "globe",
        "book",
        "cube.transparent",
        "paperplane",
        "folder",
        "leaf",
        "puzzlepiece"
    ]
    private static let workspaceColorPool = [
        "#6366F1",
        "#F97316",
        "#10B981",
        "#EC4899",
        "#0EA5E9",
        "#F59E0B",
        "#8B5CF6",
        "#14B8A6",
        "#EF4444",
        "#22C55E"
    ]
#if os(macOS)
    private static let modernUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
#else
    private static let modernUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
#endif
    private var hasLoadedInitialPage = false
    private var isRestoringSession = false
    private var webViews: [UUID: WKWebView]
    private var webViewToTabID: [ObjectIdentifier: UUID]
    private var progressObservations: [UUID: NSKeyValueObservation]
    private var pendingURLs: [UUID: URL]
    private var closedTabHistory: [ClosedTabSnapshot]
#if os(macOS)
    private var tabSidebarAppearances: [UUID: BrowserSidebarAppearance]
    private var popOutControllers: [UUID: PopOutWindowController]
#endif
    private var downloadIDs: [ObjectIdentifier: UUID]
    private var downloadDestinations: [UUID: URL]
    private var isAddressFieldFocused = false

    init(settings: BrowserSettings, userDefaults: UserDefaults = .standard) {
        self.settings = settings
        self.sessionDefaults = userDefaults
        self.tabs = []
        self.sidebarAppearance = .default
        self.splitViewTabIDs = []
        self.webViews = [:]
        self.webViewToTabID = [:]
        self.progressObservations = [:]
        self.pendingURLs = [:]
        self.closedTabHistory = []
#if os(macOS)
        self.tabSidebarAppearances = [:]
        self.poppedOutTabIDs = []
        self.popOutControllers = [:]
#endif
        self.splitViewOrientation = .horizontal
        self.splitViewFractions = [:]
        self.downloads = []
        self.downloadIDs = [:]
        self.downloadDestinations = [:]
        self.history = BrowserViewModel.loadHistory(from: userDefaults)
        self.addressSuggestions = []
        self.isShowingAddressSuggestions = false
        self.highlightedAddressSuggestionID = nil
        self.workspaces = [
            Workspace(
                id: UUID(),
                name: "The Browser",
                iconName: BrowserViewModel.randomWorkspaceIcon(),
                colorHex: BrowserViewModel.randomWorkspaceColor(),
                createdAt: Date(),
                pinnedTabs: [],
                savedTabs: [],
                notes: [
                    Workspace.Note(id: UUID(), text: "Capture sparks of inspiration and return when you're ready to build.", createdAt: Date())
                ],
                links: [],
                images: []
            )
        ]
        self.selectedWorkspaceID = nil

        super.init()
        restorePreviousSessionIfNeeded()
    }

    static func randomWorkspaceIcon() -> String {
        workspaceIconPool.randomElement() ?? "folder"
    }

    static func randomWorkspaceColor() -> String {
        workspaceColorPool.randomElement() ?? "#3B82F6"
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
        if tabs.isEmpty {
            openNewTab(with: homeURL)
        }
    }

    func revealDownload(_ id: UUID) {
        guard let item = downloads.first(where: { $0.id == id }) else { return }
        guard case .finished(let url) = item.state else { return }
#if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([url])
#elseif os(iOS)
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
#endif
    }

    func removeDownload(_ id: UUID) {
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            downloads.remove(at: index)
        }
        downloadDestinations.removeValue(forKey: id)
        if let entry = downloadIDs.first(where: { $0.value == id }) {
            downloadIDs.removeValue(forKey: entry.key)
        }
    }

    // MARK: - Workspaces

    func workspace(with id: UUID) -> Workspace? {
        workspaces.first(where: { $0.id == id })
    }

    func createWorkspace(title: String = "New Workspace") {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "Untitled Workspace" : trimmed
        let workspace = Workspace(
            id: UUID(),
            name: name,
            iconName: BrowserViewModel.randomWorkspaceIcon(),
            colorHex: BrowserViewModel.randomWorkspaceColor(),
            createdAt: Date(),
            pinnedTabs: [],
            savedTabs: [],
            notes: [],
            links: [],
            images: []
        )
        workspaces.insert(workspace, at: 0)
        selectedWorkspaceID = workspace.id
    }

    func deleteWorkspace(_ id: UUID) {
        if let index = workspaces.firstIndex(where: { $0.id == id }) {
            workspaces.remove(at: index)
        }
        if selectedWorkspaceID == id {
            selectedWorkspaceID = nil
        }
    }

    func renameWorkspace(_ id: UUID, to name: String) {
        updateWorkspace(id) { workspace in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            workspace.name = trimmed.isEmpty ? workspace.name : trimmed
        }
    }

    func updateWorkspaceIcon(_ id: UUID, to iconName: String) {
        updateWorkspace(id) { workspace in
            let trimmed = iconName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            workspace.iconName = trimmed
        }
    }

    func selectWorkspace(_ id: UUID) {
        guard workspaces.contains(where: { $0.id == id }) else { return }
        selectedWorkspaceID = id
    }

    func isWorkspaceSelected(_ id: UUID) -> Bool {
        selectedWorkspaceID == id
    }

    func clearWorkspaceSelection() {
        selectedWorkspaceID = nil
    }

    func pinCurrentTab(in workspaceID: UUID) {
        guard let tab = currentTab else { return }
        let pinned = Workspace.PinnedTab(
            id: UUID(),
            title: tab.title,
            url: tab.currentURL ?? URL(string: tab.addressBarText.trimmingCharacters(in: .whitespacesAndNewlines)),
            capturedAt: Date()
        )
        updateWorkspace(workspaceID) { workspace in
            if !workspace.pinnedTabs.contains(where: { $0.url == pinned.url && $0.title == pinned.title }) {
                workspace.pinnedTabs.insert(pinned, at: 0)
            }
        }
    }

    func saveCurrentTab(to workspaceID: UUID) {
        guard let tabID = selectedTabID else { return }
        saveTab(tabID, to: workspaceID)
    }

    func saveTab(_ tabID: UUID, to workspaceID: UUID) {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let tab = tabs[tabIndex]
        guard tab.kind == .web else { return }
        let saved = Workspace.SavedTab(
            id: UUID(),
            title: tab.displayTitle,
            url: resolvedURL(for: tabID, tab: tab),
            capturedAt: Date()
        )

        updateWorkspace(workspaceID) { workspace in
            if !workspace.savedTabs.contains(where: { existing in
                existing.title == saved.title && existing.url == saved.url
            }) {
                workspace.savedTabs.insert(saved, at: 0)
            }
        }
    }

    func removePinnedTab(in workspaceID: UUID, pinnedID: UUID) {
        updateWorkspace(workspaceID) { workspace in
            if let index = workspace.pinnedTabs.firstIndex(where: { $0.id == pinnedID }) {
                workspace.pinnedTabs.remove(at: index)
            }
        }
    }

    func openPinnedTab(workspaceID: UUID, pinnedID: UUID) {
        guard let workspace = workspace(with: workspaceID),
              let pinned = workspace.pinnedTabs.first(where: { $0.id == pinnedID }),
              let url = pinned.url
        else { return }
        openNewTab(with: url)
    }

    func removeSavedTab(in workspaceID: UUID, savedID: UUID) {
        updateWorkspace(workspaceID) { workspace in
            if let index = workspace.savedTabs.firstIndex(where: { $0.id == savedID }) {
                workspace.savedTabs.remove(at: index)
            }
        }
    }

    func openSavedTab(workspaceID: UUID, savedID: UUID) {
        guard let workspace = workspace(with: workspaceID),
              let saved = workspace.savedTabs.first(where: { $0.id == savedID }),
              let url = saved.url
        else { return }
        openNewTab(with: url)
    }

    func addNote(to workspaceID: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let note = Workspace.Note(id: UUID(), text: trimmed, createdAt: Date())
        updateWorkspace(workspaceID) { workspace in
            workspace.notes.insert(note, at: 0)
        }
    }

    func removeNote(in workspaceID: UUID, noteID: UUID) {
        updateWorkspace(workspaceID) { workspace in
            if let index = workspace.notes.firstIndex(where: { $0.id == noteID }) {
                workspace.notes.remove(at: index)
            }
        }
    }

    func addLink(to workspaceID: UUID, title: String, urlString: String) {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }
        let link = Workspace.Link(
            id: UUID(),
            title: title,
            url: URL(string: trimmedURL),
            createdAt: Date()
        )
        updateWorkspace(workspaceID) { workspace in
            workspace.links.insert(link, at: 0)
        }
    }

    func removeLink(in workspaceID: UUID, linkID: UUID) {
        updateWorkspace(workspaceID) { workspace in
            if let index = workspace.links.firstIndex(where: { $0.id == linkID }) {
                workspace.links.remove(at: index)
            }
        }
    }

    func openLink(workspaceID: UUID, linkID: UUID) {
        guard let workspace = workspace(with: workspaceID),
              let link = workspace.links.first(where: { $0.id == linkID }),
              let url = link.url
        else { return }
        openNewTab(with: url)
    }

    func addImage(to workspaceID: UUID, urlString: String, caption: String) {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, let url = URL(string: trimmedURL) else { return }
        addImage(to: workspaceID, url: url, caption: caption)
    }

    func addImage(to workspaceID: UUID, url: URL, caption: String = "") {
        let resource = Workspace.ImageResource(
            id: UUID(),
            url: url,
            caption: caption,
            createdAt: Date()
        )
        updateWorkspace(workspaceID) { workspace in
            if !workspace.images.contains(where: { $0.url == resource.url }) {
                workspace.images.insert(resource, at: 0)
            }
        }
    }

    func removeImage(in workspaceID: UUID, imageID: UUID) {
        updateWorkspace(workspaceID) { workspace in
            if let index = workspace.images.firstIndex(where: { $0.id == imageID }) {
                workspace.images.remove(at: index)
            }
        }
    }

    private func updateWorkspace(_ id: UUID, _ update: (inout Workspace) -> Void) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        update(&workspaces[index])
    }

    func handleIncomingURL(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }

#if os(macOS)
        NSApplication.shared.activate(ignoringOtherApps: true)
#endif

        hasLoadedInitialPage = true

        if tabs.isEmpty {
            openNewTab(with: url)
            return
        }

        if let selectedTabID,
           let index = tabs.firstIndex(where: { $0.id == selectedTabID }),
           tabs[index].kind != .web {
            load(url: url, in: selectedTabID)
        } else {
            openNewTab(with: url)
        }
    }

    func openNewTab() {
        openNewTab(with: homeURL)
    }

    func openHistoryTab() {
        clearAddressSuggestions()

        if let existing = tabs.first(where: { $0.kind == .history }) {
            selectedTabID = existing.id
            return
        }

        let tabID = UUID()
        let historyTab = TabState(
            id: tabID,
            title: defaultTitle(for: .history),
            addressBarText: "",
            canGoBack: false,
            canGoForward: false,
            isLoading: false,
            progress: 0,
            currentURL: nil,
            kind: .history
        )

        tabs.append(historyTab)
        selectedTabID = tabID
    }

    func openNewTab(with url: URL?) {
        clearAddressSuggestions()
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

    func isTabInSplitView(_ id: UUID) -> Bool {
        splitViewTabIDs.contains(id)
    }

    func splitFractions(for tabIDs: [UUID]) -> [UUID: CGFloat] {
        ensureSplitFractions(for: tabIDs)
        return tabIDs.reduce(into: [:]) { result, id in
            result[id] = splitViewFractions[id] ?? 0
        }
    }

    func adjustSplit(after index: Int, by delta: CGFloat, tabIDs: [UUID]) {
        guard tabIDs.count > 1,
              index >= 0,
              index < tabIDs.count - 1 else { return }

        ensureSplitFractions(for: tabIDs)

        let leadingID = tabIDs[index]
        let trailingID = tabIDs[index + 1]
        guard let leadingValue = splitViewFractions[leadingID],
              let trailingValue = splitViewFractions[trailingID] else { return }

        let combined = max(0, leadingValue + trailingValue)
        guard combined > 0 else { return }

        let minFraction = min(max(0.05, 1.0 / CGFloat(tabIDs.count * 5)), combined / 2)

        var newLeading = leadingValue + delta
        var newTrailing = trailingValue - delta

        if newLeading < minFraction {
            newLeading = minFraction
            newTrailing = combined - newLeading
        }

        if newTrailing < minFraction {
            newTrailing = minFraction
            newLeading = combined - newTrailing
        }

        newLeading = min(max(newLeading, minFraction), combined - minFraction)
        newTrailing = combined - newLeading

        splitViewFractions[leadingID] = newLeading
        splitViewFractions[trailingID] = newTrailing

        normalizeSplitFractions(for: tabIDs)
    }

    func toggleSplitOrientation() {
        splitViewOrientation = splitViewOrientation == .horizontal ? .vertical : .horizontal
    }

    func toggleSplitView(for id: UUID) {
        guard canShowTabInSplitView(id) else { return }
        if let index = splitViewTabIDs.firstIndex(of: id) {
            splitViewTabIDs.remove(at: index)
        } else {
            splitViewTabIDs.append(id)
        }
        sanitizeSplitViewTabs()
    }

    func canShowTabInSplitView(_ id: UUID) -> Bool {
        guard id != selectedTabID else { return false }
        return canDisplayTabInPrimaryArea(id)
    }

#if os(macOS)
    func togglePopOut(for id: UUID) {
        if isTabPoppedOut(id) {
            restoreTabFromPopOut(id)
            selectedTabID = id
        } else {
            popOutTab(id)
        }
    }

    func canPopOutTab(_ id: UUID) -> Bool {
        canDisplayTabInPrimaryArea(id)
    }
#else
    func togglePopOut(for id: UUID) {}

    func canPopOutTab(_ id: UUID) -> Bool { false }
#endif

    func selectTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
    }

    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[index]
        recordClosedTab(for: id, tab: tab)
#if os(macOS)
        if isTabPoppedOut(id) {
            restoreTabFromPopOut(id)
        }
#endif
        splitViewTabIDs.removeAll { $0 == id }
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

        sanitizeSplitViewTabs()
    }

    func closeCurrentTab() {
        guard let id = selectedTabID else { return }
        closeTab(id)
    }

    func reopenLastClosedTab() {
        guard let snapshot = closedTabHistory.popLast() else { return }

        let tabID = UUID()
        let resolvedKind: TabState.Kind
        let targetURL: URL?

        switch snapshot.kind {
        case .web:
            let candidateURL = snapshot.url ?? homeURL
            resolvedKind = candidateURL == nil ? .nativeHome : .web
            targetURL = candidateURL
        case .history:
            resolvedKind = .history
            targetURL = nil
        case .nativeHome:
            resolvedKind = .nativeHome
            targetURL = homeURL
        }

        let addressText: String
        if resolvedKind == .web, let targetURL {
            addressText = snapshot.addressBarText.isEmpty ? targetURL.absoluteString : snapshot.addressBarText
        } else {
            addressText = ""
        }

        let title: String
        if resolvedKind == .history {
            title = defaultTitle(for: .history)
        } else if snapshot.title.isEmpty {
            title = defaultTitle(for: resolvedKind)
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
            kind: resolvedKind
        )

        tabs.append(restoredTab)
        selectedTabID = tabID
        if let url = targetURL, resolvedKind == .web {
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
        highlightedAddressSuggestionID = nil
        updateAddressSuggestions(for: text)
    }

    func submitAddress() {
        guard let id = selectedTabID,
              let index = tabs.firstIndex(where: { $0.id == id }) else { return }

        let input = tabs[index].addressBarText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        if acceptAddressSuggestion(matching: input) {
            return
        }

        let targetURL: URL
        if let url = BrowserViewModel.url(from: input) {
            targetURL = url
        } else {
            targetURL = settings.searchURL(for: input)
        }

        clearAddressSuggestions()
        load(url: targetURL, in: id)
    }

    func performSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let targetURL = settings.searchURL(for: trimmed)

        if tabs.isEmpty || selectedTabID == nil {
            openNewTab(with: targetURL)
        } else {
            load(url: targetURL)
        }
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
#if os(macOS)
        updatePopOutWindowTitle(for: id)
#endif
        pendingURLs[id] = url
        _ = makeConfiguredWebView(for: id)
        attemptToLoadPendingURL(for: id)
        clearAddressSuggestions()
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

    func setAddressFieldFocus(_ isFocused: Bool) {
        isAddressFieldFocused = isFocused
        if isFocused {
            updateAddressSuggestions(for: currentAddressText)
        } else {
            clearAddressSuggestions()
        }
    }

    func selectAddressSuggestion(_ entry: HistoryEntry) {
        guard let id = selectedTabID,
              let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].addressBarText = entry.url.absoluteString
        clearAddressSuggestions()
        load(url: entry.url, in: id)
    }

    func openHistoryEntry(_ entry: HistoryEntry, inNewTab: Bool = false) {
        if inNewTab || selectedTabID == nil || currentTabKind == .history {
            openNewTab(with: entry.url)
            return
        }

        load(url: entry.url)
    }

    @discardableResult
    func highlightNextAddressSuggestion() -> Bool {
        moveHighlightedAddressSuggestion(by: 1)
    }

    @discardableResult
    func highlightPreviousAddressSuggestion() -> Bool {
        moveHighlightedAddressSuggestion(by: -1)
    }

    func setHighlightedAddressSuggestion(_ entry: HistoryEntry?) {
        guard let entry else {
            highlightedAddressSuggestionID = nil
            return
        }

        guard addressSuggestions.contains(entry) else { return }
        highlightedAddressSuggestionID = entry.id
    }

    func dismissAddressSuggestions() {
        clearAddressSuggestions()
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

    func isTabPoppedOut(_ id: UUID) -> Bool {
#if os(macOS)
        return poppedOutTabIDs.contains(id)
#else
        return false
#endif
    }

    private func canDisplayTabInPrimaryArea(_ id: UUID) -> Bool {
        guard let tab = tabs.first(where: { $0.id == id }) else { return false }
        guard tab.kind == .web else { return false }
        return !isTabPoppedOut(id)
    }

    private func sanitizeSplitViewTabs() {
        var seen: Set<UUID> = []
        splitViewTabIDs = splitViewTabIDs.filter { id in
            guard id != selectedTabID,
                  let tab = tabs.first(where: { $0.id == id }),
                  tab.kind == .web else { return false }
#if os(macOS)
            guard !poppedOutTabIDs.contains(id) else { return false }
#endif
            if seen.contains(id) {
                return false
            }
            seen.insert(id)
            return true
        }
        ensureSplitFractions(for: computeActiveWebViewTabIDs())
    }

    private func computeActiveWebViewTabIDs() -> [UUID] {
        var identifiers: [UUID] = []
        if let selectedTabID, canDisplayTabInPrimaryArea(selectedTabID) {
            identifiers.append(selectedTabID)
        }
        for id in splitViewTabIDs {
            guard id != selectedTabID, canDisplayTabInPrimaryArea(id) else { continue }
            identifiers.append(id)
        }
        return identifiers
    }

    private func ensureSplitFractions(for tabIDs: [UUID]) {
        guard !tabIDs.isEmpty else {
            if !splitViewFractions.isEmpty {
                splitViewFractions = [:]
            }
            return
        }

        var fractions: [UUID: CGFloat] = [:]
        var needsEqualDistribution = false
        for id in tabIDs {
            if let value = splitViewFractions[id], value > 0 {
                fractions[id] = value
            } else {
                needsEqualDistribution = true
                fractions[id] = 0
            }
        }

        if needsEqualDistribution {
            let equal = 1.0 / CGFloat(tabIDs.count)
            for id in tabIDs {
                fractions[id] = equal
            }
        } else {
            let total = fractions.values.reduce(0, +)
            if total <= 0 {
                let equal = 1.0 / CGFloat(tabIDs.count)
                for id in tabIDs {
                    fractions[id] = equal
                }
            } else {
                for id in tabIDs {
                    fractions[id] = (fractions[id] ?? 0) / total
                }
            }
        }

        var changed = splitViewFractions.count != fractions.count
        if !changed {
            for (id, value) in fractions {
                guard let existing = splitViewFractions[id] else {
                    changed = true
                    break
                }
                if abs(existing - value) > 0.0001 {
                    changed = true
                    break
                }
            }
        }

        if changed {
            splitViewFractions = fractions
        }
    }

    private func normalizeSplitFractions(for tabIDs: [UUID]) {
        let total = tabIDs.reduce(into: 0 as CGFloat) { result, id in
            result += splitViewFractions[id] ?? 0
        }
        guard total > 0 else { return }
        for id in tabIDs {
            splitViewFractions[id] = (splitViewFractions[id] ?? 0) / total
        }
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
        splitViewTabIDs.removeAll { $0 == id }
#if os(macOS)
        updatePopOutWindowTitle(for: id)
#endif
        sanitizeSplitViewTabs()
        clearAddressSuggestions()
    }

    private func defaultTitle(for kind: TabState.Kind) -> String {
        switch kind {
        case .nativeHome:
            return "Hello"
        case .history:
            return "History"
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
        // configuration.allowsPictureInPictureMediaPlayback = true
#if os(macOS)
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        configuration.preferences.setValue(true, forKey: "fullScreenEnabled")
        configuration.allowsAirPlayForMediaPlayback = true
#else
        configuration.allowsInlineMediaPlayback = true
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
#if os(macOS) || os(iOS)
        webView.customUserAgent = Self.modernUserAgent
#endif

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
            url: url,
            kind: tab.kind
        )

        closedTabHistory.append(snapshot)
        if closedTabHistory.count > 20 {
            closedTabHistory.removeFirst(closedTabHistory.count - 20)
        }
    }

    private func resolvedURL(for tabID: UUID, tab: TabState) -> URL? {
        if let webViewURL = webViews[tabID]?.url {
            return webViewURL
        }

        if let currentURL = tab.currentURL {
            return currentURL
        }

        return BrowserViewModel.url(from: tab.addressBarText)
    }

    private func persistSessionIfNeeded() {
        guard !isRestoringSession else { return }
        persistSession()
    }

    private func persistSession() {
        let persistedTabs = tabs.map { tab -> PersistedTab in
            let urlString = resolvedURL(for: tab.id, tab: tab)?.absoluteString
            let persistedKind: PersistedTab.Kind
            switch tab.kind {
            case .web:
                persistedKind = .web
            case .history:
                persistedKind = .history
            case .nativeHome:
                persistedKind = .nativeHome
            }
            return PersistedTab(kind: persistedKind, url: urlString)
        }

        let selectedIndex: Int?
        if let selectedID = selectedTabID,
           let index = tabs.firstIndex(where: { $0.id == selectedID }) {
            selectedIndex = index
        } else {
            selectedIndex = nil
        }

        let session = PersistedSession(tabs: persistedTabs, selectedIndex: selectedIndex)

        guard !session.tabs.isEmpty else {
            sessionDefaults.removeObject(forKey: Self.sessionStorageKey)
            return
        }

        if let data = try? JSONEncoder().encode(session) {
            sessionDefaults.set(data, forKey: Self.sessionStorageKey)
        }
    }

    private func restorePreviousSessionIfNeeded() {
        guard
            let data = sessionDefaults.data(forKey: Self.sessionStorageKey),
            let session = try? JSONDecoder().decode(PersistedSession.self, from: data),
            !session.tabs.isEmpty
        else {
            return
        }

        isRestoringSession = true

        var restoredTabs: [TabState] = []
        var restoredTabIDs: [UUID] = []

        for persisted in session.tabs {
            let id = UUID()
            let url = persisted.url.flatMap { URL(string: $0) }
            let kind: TabState.Kind
            switch persisted.kind {
            case .web:
                if let url {
                    kind = .web
                } else {
                    kind = .nativeHome
                }
            case .nativeHome:
                kind = .nativeHome
            case .history:
                kind = .history
            }
            let addressText = url?.absoluteString ?? ""

            let tab = TabState(
                id: id,
                title: defaultTitle(for: kind),
                addressBarText: addressText,
                canGoBack: false,
                canGoForward: false,
                isLoading: false,
                progress: 0,
                currentURL: url,
                kind: kind
            )

            restoredTabs.append(tab)
            restoredTabIDs.append(id)
        }

        tabs = restoredTabs

        if let selectedIndex = session.selectedIndex,
           selectedIndex >= 0,
           selectedIndex < restoredTabIDs.count {
            selectedTabID = restoredTabIDs[selectedIndex]
        } else {
            selectedTabID = restoredTabIDs.first
        }

        hasLoadedInitialPage = true

        for (index, persisted) in session.tabs.enumerated() {
            guard persisted.kind == .web,
                  let urlString = persisted.url,
                  let url = URL(string: urlString)
            else { continue }

            let tabID = restoredTabIDs[index]
            pendingURLs[tabID] = url
            let webView = makeConfiguredWebView(for: tabID)
            if webView.url == nil {
                attemptToLoadPendingURL(for: tabID)
            }
        }

        isRestoringSession = false
        persistSession()
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

    private func downloadID(for download: WKDownload) -> UUID? {
        downloadIDs[ObjectIdentifier(download)]
    }

    private func registerDownload(_ download: WKDownload, suggestedFilename: String?, sourceURL: URL?) {
        let identifier = ObjectIdentifier(download)
        if let existingID = downloadIDs[identifier] {
            if let filename = suggestedFilename {
                let sanitized = sanitizeFilename(filename)
                updateDownload(id: existingID) { item in
                    item.filename = sanitized
                }
            }
            if let sourceURL {
                updateDownload(id: existingID) { item in
                    item.sourceURL = sourceURL
                }
            }
            return
        }

        let id = UUID()
        download.delegate = self
        downloadIDs[identifier] = id
        let filename = sanitizeFilename(suggestedFilename ?? sourceURL?.lastPathComponent ?? "Download")
        let item = DownloadItem(id: id, filename: filename, state: .preparing, sourceURL: sourceURL)
        downloads.append(item)
    }

    private func updateDownload(id: UUID, mutate: (inout DownloadItem) -> Void) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        mutate(&downloads[index])
    }

    private func finalizeDownload(_ download: WKDownload) {
        let identifier = ObjectIdentifier(download)
        if let id = downloadIDs.removeValue(forKey: identifier) {
            downloadDestinations.removeValue(forKey: id)
        }
    }

    private func downloadsDirectory() -> URL {
#if os(macOS)
        let searchDirectory: FileManager.SearchPathDirectory = .downloadsDirectory
#else
        let searchDirectory: FileManager.SearchPathDirectory = .documentDirectory
#endif
        let directory = FileManager.default.urls(for: searchDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return directory
    }

    private func uniqueDestination(for filename: String, in directory: URL) -> URL {
        let baseName = (filename as NSString).deletingPathExtension
        let fileExtension = (filename as NSString).pathExtension
        var attempt = 0
        var candidate: URL
        repeat {
            let name: String
            if attempt == 0 {
                name = filename
            } else if fileExtension.isEmpty {
                name = "\(baseName) (\(attempt))"
            } else {
                name = "\(baseName) (\(attempt)).\(fileExtension)"
            }
            candidate = directory.appendingPathComponent(name)
            attempt += 1
        } while FileManager.default.fileExists(atPath: candidate.path)
        return candidate
    }

    private func sanitizeFilename(_ filename: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "\\/:*?\"<>|")
        var cleaned = filename.components(separatedBy: invalidCharacters).joined(separator: "_")
        if cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cleaned = "Download"
        }
        return cleaned
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

    private func popOutTab(_ id: UUID) {
        guard canPopOutTab(id), !isTabPoppedOut(id) else { return }
        let webView = makeConfiguredWebView(for: id)
        let controller = PopOutWindowController(
            viewModel: self,
            tabID: id,
            webView: webView,
            title: tabDisplayTitle(for: id)
        )
        popOutControllers[id] = controller
        poppedOutTabIDs.insert(id)
        splitViewTabIDs.removeAll { $0 == id }
        if selectedTabID == id {
            selectedTabID = nextAvailableTab(excluding: id)
        }
        controller.show()
    }

    private func restoreTabFromPopOut(_ id: UUID) {
        guard let controller = popOutControllers[id] else {
            poppedOutTabIDs.remove(id)
            sanitizeSplitViewTabs()
            return
        }
        poppedOutTabIDs.remove(id)
        controller.closeForRestoration()
    }

    fileprivate func finalizePopOutRestoration(for id: UUID) {
        popOutControllers.removeValue(forKey: id)
        sanitizeSplitViewTabs()
        updateSidebarAppearanceForSelection()
    }

    fileprivate func handlePopOutWindowClosed(for id: UUID) {
        poppedOutTabIDs.remove(id)
        popOutControllers.removeValue(forKey: id)
        sanitizeSplitViewTabs()
        if selectedTabID == nil || selectedTabID == id {
            selectedTabID = id
        }
    }

    private func nextAvailableTab(excluding id: UUID) -> UUID? {
        tabs.first { candidate in
            candidate.id != id && !isTabPoppedOut(candidate.id)
        }?.id
    }

    private func updatePopOutWindowTitle(for id: UUID) {
        guard let controller = popOutControllers[id] else { return }
        controller.updateTitle(tabDisplayTitle(for: id))
    }

    private func tabDisplayTitle(for id: UUID) -> String {
        guard let tab = tabs.first(where: { $0.id == id }) else { return "" }
        return tab.displayTitle
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

    private func updateAddressSuggestions(for text: String) {
        guard isAddressFieldFocused else {
            isShowingAddressSuggestions = false
            addressSuggestions = []
            highlightedAddressSuggestionID = nil
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        let suggestions: [HistoryEntry]
        if lowercased.isEmpty {
            suggestions = history.sorted { $0.lastVisited > $1.lastVisited }
        } else {
            suggestions = history.filter { entry in
                entry.displayTitle.lowercased().contains(lowercased) ||
                entry.displayURL.lowercased().contains(lowercased)
            }
            .sorted { lhs, rhs in
                if lhs.lastVisited == rhs.lastVisited {
                    return lhs.visitCount > rhs.visitCount
                }
                return lhs.lastVisited > rhs.lastVisited
            }
        }

        let newSuggestions = Array(suggestions.prefix(8))
        addressSuggestions = newSuggestions
        isShowingAddressSuggestions = !addressSuggestions.isEmpty

        if let highlightedID = highlightedAddressSuggestionID,
           newSuggestions.contains(where: { $0.id == highlightedID }) {
            return
        }

        highlightedAddressSuggestionID = nil
    }

    private func clearAddressSuggestions() {
        addressSuggestions = []
        isShowingAddressSuggestions = false
        highlightedAddressSuggestionID = nil
    }

    private func acceptAddressSuggestion(matching input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        guard let highlightedID = highlightedAddressSuggestionID,
              let highlighted = addressSuggestions.first(where: { $0.id == highlightedID }) else {
            return false
        }

        selectAddressSuggestion(highlighted)
        return true
    }

    @discardableResult
    private func moveHighlightedAddressSuggestion(by offset: Int) -> Bool {
        guard !addressSuggestions.isEmpty else {
            highlightedAddressSuggestionID = nil
            return false
        }

        let currentIndex = addressSuggestions.firstIndex { $0.id == highlightedAddressSuggestionID }
        let newIndex: Int

        if let currentIndex {
            newIndex = (currentIndex + offset + addressSuggestions.count) % addressSuggestions.count
        } else {
            newIndex = offset > 0 ? 0 : addressSuggestions.count - 1
        }

        highlightedAddressSuggestionID = addressSuggestions[newIndex].id
        return true
    }

    private func recordHistoryVisit(url: URL, title: String?) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        let normalizedURL = BrowserViewModel.normalizedHistoryKey(for: url)
        let visitTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle: String
        if let visitTitle, !visitTitle.isEmpty {
            resolvedTitle = visitTitle
        } else if let host = url.host {
            resolvedTitle = host
        } else {
            resolvedTitle = url.absoluteString
        }

        var updatedHistory = history

        if let index = updatedHistory.firstIndex(where: { $0.normalizedURL == normalizedURL }) {
            var entry = updatedHistory[index]
            entry.title = resolvedTitle
            entry.lastVisited = Date()
            entry.visitCount += 1
            entry.url = url
            updatedHistory[index] = entry
        } else {
            let entry = HistoryEntry(
                id: UUID(),
                url: url,
                title: resolvedTitle,
                lastVisited: Date(),
                visitCount: 1,
                normalizedURL: normalizedURL
            )
            updatedHistory.append(entry)
        }

        updatedHistory.sort { $0.lastVisited > $1.lastVisited }
        if updatedHistory.count > BrowserViewModel.historyLimit {
            updatedHistory = Array(updatedHistory.prefix(BrowserViewModel.historyLimit))
        }

        history = updatedHistory
        if isAddressFieldFocused {
            updateAddressSuggestions(for: currentAddressText)
        }
        persistHistory()
    }

    private func persistHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        sessionDefaults.set(data, forKey: BrowserViewModel.historyStorageKey)
    }

    private static func loadHistory(from defaults: UserDefaults) -> [HistoryEntry] {
        guard let data = defaults.data(forKey: BrowserViewModel.historyStorageKey),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.lastVisited > $1.lastVisited }
    }

    private static func normalizedHistoryKey(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString.lowercased()
        }
        components.fragment = nil
        if components.path.isEmpty {
            components.path = "/"
        }
        let normalized = components.string ?? url.absoluteString
        return normalized.lowercased()
    }
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
        case .history:
            return "History"
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

extension BrowserViewModel: WKUIDelegate {
#if os(macOS)
    @available(macOS 12.0, *)
    func webView(_ webView: WKWebView, contextMenuItemsForElement elementInfo: WKContextMenuElementInfo, defaultMenuItems: [WKContextMenuItem]) -> [WKContextMenuItem] {
        guard let imageURL = elementInfo.imageURL else {
            return defaultMenuItems
        }

        guard !workspaces.isEmpty else { return defaultMenuItems }

        var items = defaultMenuItems
        let additions = workspaces.map { workspace in
            WKContextMenuItem(title: "Save Image to \(workspace.name)") { [weak self] in
                self?.addImage(to: workspace.id, url: imageURL)
            }
        }

        if !additions.isEmpty {
            items.append(WKContextMenuItem.separator())
            items.append(contentsOf: additions)
        }

        return items
    }

#endif

#if os(iOS)
    func webView(_ webView: WKWebView, contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo, completionHandler: @escaping (UIContextMenuConfiguration?) -> Void) {
        guard let imageURL = elementInfo.imageURL, !workspaces.isEmpty else {
            completionHandler(nil)
            return
        }

        completionHandler(UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { suggested in
            let actions = self.workspaces.map { workspace in
                let icon = UIImage(systemName: workspace.iconName) ?? UIImage(systemName: "folder")
                return UIAction(title: "Save to \(workspace.name)", image: icon) { _ in
                    self.addImage(to: workspace.id, url: imageURL)
                }
            }

            let spaceMenu = UIMenu(title: "Save Image to Workspace", options: .displayInline, children: actions)
            if let suggested {
                return UIMenu(children: [spaceMenu] + suggested.children)
            } else {
                return UIMenu(children: [spaceMenu])
            }
        })
    }
#endif
}

extension BrowserViewModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if #available(macOS 11.3, iOS 14.5, *) {
            if navigationAction.shouldPerformDownload {
                decisionHandler(.download)
                return
            }
        }

        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            if shouldOpenNewTab(for: url) {
                openNewTab(with: url)
                decisionHandler(.cancel)
                return
            }
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if !navigationResponse.canShowMIMEType {
            decisionHandler(.download)
            return
        }

        if let httpResponse = navigationResponse.response as? HTTPURLResponse,
           let disposition = httpResponse.value(forHTTPHeaderField: "Content-Disposition")?.lowercased(),
           disposition.contains("attachment") {
            decisionHandler(.download)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        registerDownload(download, suggestedFilename: nil, sourceURL: navigationAction.request.url)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        registerDownload(download, suggestedFilename: navigationResponse.response.suggestedFilename, sourceURL: navigationResponse.response.url)
    }

    @available(macOS 11.3, iOS 14.5, *)
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, willPerformDownload download: WKDownload) {
        registerDownload(download, suggestedFilename: navigationAction.request.url?.lastPathComponent, sourceURL: navigationAction.request.url)
    }

    @available(macOS 11.3, iOS 14.5, *)
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, willPerformDownload download: WKDownload) {
        registerDownload(download, suggestedFilename: navigationResponse.response.suggestedFilename, sourceURL: navigationResponse.response.url)
    }

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
        updatePopOutWindowTitle(for: tabID)
#endif
        if let url = webView.url {
            recordHistoryVisit(url: url, title: webView.title)
        }
        clearAddressSuggestions()
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

    private func shouldOpenNewTab(for url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }

        switch scheme {
        case "http", "https":
            return true
        default:
            return false
        }
    }
}

extension BrowserViewModel: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        guard let id = downloadID(for: download) else {
            completionHandler(nil)
            return
        }

        let filename = sanitizeFilename(suggestedFilename)
        let directory = downloadsDirectory()
        let destination = uniqueDestination(for: filename, in: directory)
        downloadDestinations[id] = destination
        updateDownload(id: id) { item in
            item.filename = destination.lastPathComponent
            item.state = .downloading(progress: 0)
        }
        completionHandler(destination)
    }

    func download(_ download: WKDownload, didReceive response: URLResponse, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = downloadID(for: download) else { return }
        let progress: Double?
        if totalBytesExpectedToWrite > 0 {
            progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        } else {
            progress = nil
        }
        updateDownload(id: id) { item in
            item.state = .downloading(progress: progress)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let id = downloadID(for: download) else { return }
        let destination = downloadDestinations[id] ?? downloadsDirectory().appendingPathComponent(downloads.first(where: { $0.id == id })?.filename ?? "Download")
        updateDownload(id: id) { item in
            item.state = .finished(destination)
        }
        finalizeDownload(download)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard let id = downloadID(for: download) else { return }
        updateDownload(id: id) { item in
            item.state = .failed(error.localizedDescription)
        }
        finalizeDownload(download)
    }
}

#if os(macOS)
private final class PopOutWindowController: NSObject, NSWindowDelegate {
    weak var viewModel: BrowserViewModel?
    let tabID: UUID
    let window: NSWindow
    let webView: WKWebView
    var isRestoring = false

    init(viewModel: BrowserViewModel, tabID: UUID, webView: WKWebView, title: String) {
        self.viewModel = viewModel
        self.tabID = tabID
        self.webView = webView
        self.window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1024, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = title
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        if window.contentView == nil {
            window.contentView = NSView()
        }

        attachWebView()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    func updateTitle(_ title: String) {
        window.title = title
    }

    func closeForRestoration() {
        isRestoring = true
        window.close()
    }

    private func attachWebView() {
        guard let contentView = window.contentView else { return }
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            webView.topAnchor.constraint(equalTo: contentView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    func windowWillClose(_ notification: Notification) {
        webView.removeFromSuperview()
        if isRestoring {
            viewModel?.finalizePopOutRestoration(for: tabID)
        } else {
            viewModel?.handlePopOutWindowClosed(for: tabID)
        }
    }
}
#endif
