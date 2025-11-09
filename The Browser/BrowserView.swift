import SwiftUI
#if os(macOS)
import AppKit
#endif

struct BrowserView: View {
    @StateObject private var settings: BrowserSettings
    @StateObject private var viewModel: BrowserViewModel
    @FocusState private var isAddressFocused: Bool
    @State private var isShowingSettings = false
    @State private var isWebContentFullscreen = false
#if os(macOS)
    @StateObject private var addressFieldController = AddressFieldController()
#endif
    private let sidebarWidth: CGFloat = 288

    init() {
        let settings = BrowserSettings()
        _settings = StateObject(wrappedValue: settings)
        _viewModel = StateObject(wrappedValue: BrowserViewModel(settings: settings))
    }

    var body: some View {
        let activeWebTabs = viewModel.activeWebViewTabIDs
        let currentTabKind = viewModel.currentTabKind
        ZStack(alignment: .leading) {
            Group {
                if currentTabKind == .history {
                    HistoryView(viewModel: viewModel)
                } else if activeWebTabs.isEmpty {
                    DefaultHomeView(
                        settings: settings,
                        onSubmitSearch: { query in
                            viewModel.performSearch(query)
                        },
                        onOpenURL: { url in
                            viewModel.openNewTab(with: url)
                        },
                        onOpenNewTab: {
                            viewModel.openNewTab()
                        },
                        onOpenHistory: {
                            viewModel.openHistoryTab()
                        },
                        onOpenSettings: {
                            isShowingSettings = true
                        }
                    )
                } else {
                    splitViewContent(for: activeWebTabs)
                }
            }
            .background(Color.browserBackground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.leading, isWebContentFullscreen ? 0 : sidebarWidth)
            .animation(.easeInOut(duration: 0.22), value: isWebContentFullscreen)

            if !isWebContentFullscreen {
                BrowserSidebar(
                    viewModel: viewModel,
                    appearance: viewModel.sidebarAppearance,
                    isAddressFocused: $isAddressFocused,
                    isShowingSettings: $isShowingSettings,
                    enterFullscreen: { withAnimation { isWebContentFullscreen = true } }
#if os(macOS)
                    , addressFieldController: addressFieldController
#endif
                )
                .frame(width: sidebarWidth)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            if isWebContentFullscreen {
                VStack {
                    HStack {
                        NavigationControlButton(
                            symbol: "sidebar.leading",
                            help: "Show Sidebar",
                            isEnabled: true,
                            appearance: viewModel.sidebarAppearance,
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
        .onOpenURL { url in
            viewModel.handleIncomingURL(url)
        }
#if os(macOS)
        .focusedSceneValue(\.browserActions, commandContext)
#endif
        .sheet(isPresented: $isShowingSettings) {
            SettingsPanel(settings: settings)
                .frame(width: 600, height:600)
        }
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
                DispatchQueue.main.async {
#if os(macOS)
                    addressFieldController.focus()
#endif
                    isAddressFocused = true
                }
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
            openSettings: {
                if isWebContentFullscreen {
                    withAnimation {
                        isWebContentFullscreen = false
                    }
                }
                isShowingSettings = true
            },
            canSelectNextTab: viewModel.hasMultipleTabs,
            canSelectPreviousTab: viewModel.hasMultipleTabs,
            canReopenLastClosedTab: viewModel.canReopenLastClosedTab,
            hasActiveTab: viewModel.currentTabExists
        )
    }
#endif
}

extension BrowserView {
    @ViewBuilder
    private func splitViewContent(for tabIDs: [UUID]) -> some View {
        if tabIDs.count <= 1, let id = tabIDs.first {
            BrowserWebView(viewModel: viewModel, tabID: id)
        } else {
            GeometryReader { geometry in
                let orientation = viewModel.splitViewOrientation
                let totalLength = max(orientation == .horizontal ? geometry.size.width : geometry.size.height, 1)
                let fractions = viewModel.splitFractions(for: tabIDs)

                Group {
                    if orientation == .horizontal {
                        HStack(spacing: 0) {
                            splitViewContentRows(for: tabIDs, orientation: orientation, totalLength: totalLength, fractions: fractions)
                        }
                    } else {
                        VStack(spacing: 0) {
                            splitViewContentRows(for: tabIDs, orientation: orientation, totalLength: totalLength, fractions: fractions)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.browserBackground)
            }
        }
    }

    @ViewBuilder
    private func splitViewContentRows(
        for tabIDs: [UUID],
        orientation: BrowserViewModel.SplitOrientation,
        totalLength: CGFloat,
        fractions: [UUID: CGFloat]
    ) -> some View {
        ForEach(Array(tabIDs.enumerated()), id: \.element) { index, tabID in
            BrowserWebView(viewModel: viewModel, tabID: tabID)
                .frame(
                    width: orientation == .horizontal ? max(0, totalLength * (fractions[tabID] ?? 0)) : nil,
                    height: orientation == .vertical ? max(0, totalLength * (fractions[tabID] ?? 0)) : nil
                )
                .frame(
                    maxWidth: orientation == .horizontal ? nil : .infinity,
                    maxHeight: orientation == .vertical ? nil : .infinity
                )

            if index < tabIDs.count - 1 {
                SplitDivider(orientation: orientation, totalLength: totalLength) { delta in
                    viewModel.adjustSplit(after: index, by: delta, tabIDs: tabIDs)
                }
            }
        }
    }
}

private struct SplitDivider: View {
    let orientation: BrowserViewModel.SplitOrientation
    let totalLength: CGFloat
    let dragChanged: (CGFloat) -> Void

    @State private var isDragging = false
    @State private var previousTranslation: CGFloat = 0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(isDragging ? 0.2 : 0.1))
                .frame(
                    width: orientation == .horizontal ? 10 : nil,
                    height: orientation == .vertical ? 10 : nil
                )
                .frame(
                    maxWidth: orientation == .vertical ? .infinity : 10,
                    maxHeight: orientation == .horizontal ? .infinity : 10
                )

            if orientation == .horizontal {
                Rectangle()
                    .fill(Color.white.opacity(isDragging ? 0.45 : 0.28))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            } else {
                Rectangle()
                    .fill(Color.white.opacity(isDragging ? 0.45 : 0.28))
                    .frame(height: 2)
                    .frame(maxWidth: .infinity)
            }
        }
        .contentShape(Rectangle())
#if os(macOS)
        .background(NonDraggableView())
#endif
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard totalLength > 0 else { return }
                    isDragging = true
                    let translation = orientation == .horizontal ? value.translation.width : value.translation.height
                    let delta = translation - previousTranslation
                    previousTranslation = translation
                    dragChanged(delta / totalLength)
                }
                .onEnded { _ in
                    isDragging = false
                    previousTranslation = 0
                }
        )
    }
}

#if os(macOS)
private struct NonDraggableView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NonDraggableNSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class NonDraggableNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
}
#endif

private struct AddressFieldWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct AddressFieldHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct BrowserSidebar: View {
    @ObservedObject var viewModel: BrowserViewModel
    let appearance: BrowserSidebarAppearance
    var isAddressFocused: FocusState<Bool>.Binding
    @Binding var isShowingSettings: Bool
    let enterFullscreen: () -> Void
    @State private var addressFieldWidth: CGFloat = 0
    @State private var addressFieldHeight: CGFloat = 0
#if os(macOS)
    let addressFieldController: AddressFieldController
    @State private var isInteractingWithAddressSuggestions = false
#endif

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            VStack(alignment: .leading, spacing: 14) {
                navigationControls
                addressField
            }

            divider

            tabList

            if !viewModel.downloads.isEmpty {
                divider
                downloadsSection
            }

            Spacer()

            HStack(spacing: 12) {
                shareControl

                iconControlButton(
                    systemImage: "clock",
                    help: "History",
                    isEnabled: true,
                    action: viewModel.openHistoryTab
                )

                iconControlButton(
                    systemImage: "ladybug",
                    help: "Web Inspector",
                    isEnabled: viewModel.isCurrentTabDisplayingWebContent,
                    action: viewModel.openInspector
                )

                iconControlButton(
                    systemImage: "gearshape",
                    help: "Settings",
                    isEnabled: true,
                    action: { isShowingSettings = true }
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .foregroundStyle(appearance.primary)
    .liquidGlassBackground(tint: appearance.background, cornerRadius: 0, includeShadow: false)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
#if os(macOS)
            WindowControls()
#endif

            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color.browserAccent)
                            .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 6)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("The Browser")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(appearance.primary)
                    Text("Workspace")
                        .font(.caption)
                        .foregroundStyle(appearance.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var shareControl: some View {
        if let url = viewModel.currentURL, viewModel.isCurrentTabDisplayingWebContent {
            ShareLink(item: url) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .foregroundStyle(appearance.primary)
            }
            .buttonStyle(.plain)
            .liquidGlassBackground(tint: appearance.controlTint, cornerRadius: 16, includeShadow: false)
#if os(macOS)
            .help("Share")
#endif
        } else {
            iconControlButton(
                systemImage: "square.and.arrow.up",
                help: "Share",
                isEnabled: false,
                action: {}
            )
        }
    }

    private var navigationControls: some View {
        HStack(spacing: 10) {
            NavigationControlButton(
                symbol: "chevron.left",
                help: "Back",
                isEnabled: viewModel.canGoBack,
                appearance: appearance,
                action: viewModel.goBack
            )

            NavigationControlButton(
                symbol: "chevron.right",
                help: "Forward",
                isEnabled: viewModel.canGoForward,
                appearance: appearance,
                action: viewModel.goForward
            )

            NavigationControlButton(
                symbol: viewModel.isLoading ? "xmark" : "arrow.clockwise",
                help: viewModel.isLoading ? "Stop" : "Reload",
                isEnabled: viewModel.isCurrentTabDisplayingWebContent,
                appearance: appearance,
                action: viewModel.reloadOrStop
            )

            NavigationControlButton(
                symbol: "house",
                help: "Home",
                isEnabled: viewModel.currentTabExists,
                appearance: appearance,
                action: viewModel.goHome
            )

            NavigationControlButton(
                symbol: "arrow.up.left.and.arrow.down.right",
                help: "Enter Fullscreen",
                isEnabled: viewModel.isCurrentTabDisplayingWebContent,
                appearance: appearance,
                action: enterFullscreen
            )
        }
    }

    private var addressField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Address")
                .font(.caption)
                .foregroundStyle(appearance.secondary)

            ZStack(alignment: .topLeading) {
                addressTextInput

                if viewModel.isShowingAddressSuggestions {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear
                            .frame(height: suggestionTopPadding)
                            .allowsHitTesting(false)

                        addressSuggestionsList
                    }
                    .frame(width: max(addressFieldWidth, 220))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .zIndex(1)
                }
            }
        }
        .onPreferenceChange(AddressFieldWidthPreferenceKey.self) { width in
            addressFieldWidth = width
        }
        .onPreferenceChange(AddressFieldHeightPreferenceKey.self) { height in
            addressFieldHeight = height
        }
    }

    private var suggestionTopPadding: CGFloat {
        max(addressFieldHeight, 44) + 6
    }

    private func handleAddressFocusChange(_ focused: Bool) {
#if os(macOS)
        if !focused {
            DispatchQueue.main.async {
                if isInteractingWithAddressSuggestions && viewModel.isShowingAddressSuggestions {
                    isAddressFocused.wrappedValue = true
                    addressFieldController.focus()
                } else {
                    viewModel.setAddressFieldFocus(false)
                }
            }
            return
        }
#endif
        viewModel.setAddressFieldFocus(focused)
    }

    private var addressTextInput: some View {
        let textBinding = Binding(
            get: { viewModel.currentAddressText },
            set: { viewModel.updateAddressText($0) }
        )

#if os(iOS)
        let field = TextField("Search or enter website name", text: textBinding)
            .focused(isAddressFocused)
            .textFieldStyle(.plain)
            .onChange(of: isAddressFocused.wrappedValue) { focused in
                handleAddressFocusChange(focused)
            }
            .onSubmit {
                viewModel.submitAddress()
                isAddressFocused.wrappedValue = false
            }
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .disableAutocorrection(true)
            .submitLabel(.go)
#else
        let field = MacAddressTextField(
            text: textBinding,
            isFocused: isAddressFocused,
            placeholder: "Search or enter website name",
            onSubmit: {
                viewModel.submitAddress()
                isAddressFocused.wrappedValue = false
                addressFieldController.blur()
            },
            onArrowDown: { viewModel.highlightNextAddressSuggestion() },
            onArrowUp: { viewModel.highlightPreviousAddressSuggestion() },
            onCancel: viewModel.dismissAddressSuggestions,
            onFocusChange: handleAddressFocusChange,
            controller: addressFieldController
        )
#endif

        return field
            .foregroundColor(appearance.primary)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(Color.clear)
            .overlay(alignment: .bottomLeading) {
                if viewModel.shouldShowProgress {
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.browserAccent)
                            .frame(width: geometry.size.width * max(viewModel.progress, 0), height: 3)
                    }
                    .frame(height: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(key: AddressFieldWidthPreferenceKey.self, value: geometry.size.width)
                        .preference(key: AddressFieldHeightPreferenceKey.self, value: geometry.size.height)
                }
            )
            .liquidGlassBackground(tint: appearance.controlTint, cornerRadius: 16, includeShadow: false)
            .tint(appearance.primary)
    }

    private var addressSuggestionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(viewModel.addressSuggestions) { suggestion in
                Button {
                    viewModel.selectAddressSuggestion(suggestion)
                    isAddressFocused.wrappedValue = false
                } label: {
                    suggestionRow(
                        for: suggestion,
                        isHighlighted: viewModel.highlightedAddressSuggestionID == suggestion.id
                    )
                }
                .buttonStyle(.plain)
#if os(macOS)
                .focusable(false)
#endif
#if os(macOS)
                .onHover { hovering in
                    if hovering {
                        viewModel.setHighlightedAddressSuggestion(suggestion)
                    }
                }
#endif

                if suggestion.id != viewModel.addressSuggestions.last?.id {
                    Rectangle()
                        .fill(appearance.primary.opacity(0.08))
                        .frame(height: 1)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .liquidGlassBackground(tint: appearance.controlTint.opacity(0.9), cornerRadius: 20)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
#if os(macOS)
        .onHover { hovering in
            isInteractingWithAddressSuggestions = hovering
        }
        .onDisappear {
            isInteractingWithAddressSuggestions = false
        }
#endif
    }

    private func suggestionRow(
        for suggestion: BrowserViewModel.HistoryEntry,
        isHighlighted: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(suggestion.displayTitle)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(appearance.primary)

            Text(suggestion.displayURL)
                .font(.caption2)
                .foregroundStyle(appearance.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    appearance.primary.opacity(
                        isHighlighted ? 0.18 : 0.06
                    )
                )
        )
        .padding(.horizontal, 2)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var divider: some View {
        Rectangle()
            .fill(appearance.primary.opacity(0.12))
            .frame(height: 1)
            .padding(.vertical, 4)
    }

    private var downloadsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Downloads")
                    .font(.caption)
                    .foregroundStyle(appearance.secondary)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(viewModel.downloads) { download in
                    DownloadRow(
                        download: download,
                        appearance: appearance,
                        revealAction: { viewModel.revealDownload(download.id) },
                        dismissAction: { viewModel.removeDownload(download.id) }
                    )
                }
            }
        }
    }

    private var tabList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Tabs")
                    .font(.caption)
                    .foregroundStyle(appearance.secondary)
                Spacer()
                if viewModel.activeWebViewTabIDs.count > 1 {
                    Button(action: viewModel.toggleSplitOrientation) {
                        Image(systemName: viewModel.splitViewOrientation == .horizontal ? "square.split.2x1" : "square.split.1x2")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .foregroundStyle(appearance.primary)
                    }
                    .buttonStyle(.plain)
                    .liquidGlassBackground(tint: appearance.controlTint, cornerRadius: 14, includeShadow: false)
#if os(macOS)
                    .help("Toggle Split Orientation")
#endif
                }
                Button(action: viewModel.openNewTab) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(appearance.primary)
                }
                .buttonStyle(.plain)
                .liquidGlassBackground(tint: appearance.controlTint, cornerRadius: 14, includeShadow: false)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.tabs) { tab in
#if os(macOS)
                        TabRow(
                            tab: tab,
                            isSelected: tab.id == viewModel.selectedTabID,
                            appearance: appearance,
                            selectAction: { viewModel.selectTab(tab.id) },
                            closeAction: { viewModel.closeTab(tab.id) },
                            isInSplitView: viewModel.isTabInSplitView(tab.id),
                            canShowInSplitView: viewModel.canShowTabInSplitView(tab.id),
                            toggleSplitAction: { viewModel.toggleSplitView(for: tab.id) },
                            splitOrientation: viewModel.splitViewOrientation,
                            isPoppedOut: viewModel.isTabPoppedOut(tab.id),
                            canPopOut: viewModel.canPopOutTab(tab.id),
                            togglePopOutAction: { viewModel.togglePopOut(for: tab.id) }
                        )
#else
                        TabRow(
                            tab: tab,
                            isSelected: tab.id == viewModel.selectedTabID,
                            appearance: appearance,
                            selectAction: { viewModel.selectTab(tab.id) },
                            closeAction: { viewModel.closeTab(tab.id) },
                            isInSplitView: viewModel.isTabInSplitView(tab.id),
                            canShowInSplitView: viewModel.canShowTabInSplitView(tab.id),
                            toggleSplitAction: { viewModel.toggleSplitView(for: tab.id) },
                            splitOrientation: viewModel.splitViewOrientation
                        )
#endif
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func iconControlButton(systemImage: String, help: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 42, height: 42)
                .foregroundStyle(appearance.primary)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .liquidGlassBackground(tint: appearance.controlTint, cornerRadius: 16, includeShadow: false)
        .opacity(isEnabled ? 1 : 0.45)
#if os(macOS)
        .help(help)
#endif
    }
}

private struct NavigationControlButton: View {
    let symbol: String
    let help: String
    let isEnabled: Bool
    let appearance: BrowserSidebarAppearance
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 36, height: 36)
                .foregroundStyle(appearance.primary)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .liquidGlassBackground(tint: appearance.controlTint, cornerRadius: 12, includeShadow: false)
        .opacity(isEnabled ? 1 : 0.45)
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
        }
        .buttonStyle(.plain)
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
#endif

private struct TabRow: View {
    let tab: BrowserViewModel.TabState
    let isSelected: Bool
    let appearance: BrowserSidebarAppearance
    let selectAction: () -> Void
    let closeAction: () -> Void
    let isInSplitView: Bool
    let canShowInSplitView: Bool
    let toggleSplitAction: () -> Void
    let splitOrientation: BrowserViewModel.SplitOrientation
#if os(macOS)
    let isPoppedOut: Bool
    let canPopOut: Bool
    let togglePopOutAction: () -> Void
#endif

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.displayTitle)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .foregroundStyle(appearance.primary)

                if let subtitle = tab.displaySubtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundStyle(appearance.secondary)
                }
            }

            Spacer()

            if tab.isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(appearance.primary)
            } else {
                HStack(spacing: 6) {
                    Button(action: toggleSplitAction) {
                        Image(systemName: splitToggleIcon)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 26, height: 26)
                            .foregroundStyle(appearance.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canShowInSplitView)
                    .liquidGlassBackground(
                        tint: appearance.controlTint.opacity(isInSplitView ? 1 : 0.65),
                        cornerRadius: 10,
                        includeShadow: false
                    )
                    .opacity(canShowInSplitView ? 0.9 : 0.35)
#if os(macOS)
                    .help(isInSplitView ? "Remove from Split View" : "Add to Split View")
#endif

#if os(macOS)
                    Button(action: togglePopOutAction) {
                        Image(systemName: isPoppedOut ? "arrow.down.left.square" : "arrow.up.right.square")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 26, height: 26)
                            .foregroundStyle(appearance.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canPopOut)
                    .liquidGlassBackground(
                        tint: appearance.controlTint.opacity(isPoppedOut ? 1 : 0.65),
                        cornerRadius: 10,
                        includeShadow: false
                    )
                    .opacity(canPopOut ? 0.9 : 0.35)
                    .help(isPoppedOut ? "Return to Main Window" : "Pop Out")
#endif

                    Button(action: closeAction) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 24, height: 24)
                            .foregroundStyle(appearance.primary)
                    }
                    .buttonStyle(.plain)
                    .opacity(0.7)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassBackground(
            tint: appearance.controlTint.opacity(isSelected ? 1 : 0.6),
            cornerRadius: 16,
            includeShadow: false
        )
        .opacity(isSelected ? 1 : 0.9)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: selectAction)
    }

    private var splitToggleIcon: String {
        switch splitOrientation {
        case .horizontal:
            return isInSplitView ? "square.split.2x1.fill" : "square.split.2x1"
        case .vertical:
            return isInSplitView ? "square.split.1x2.fill" : "square.split.1x2"
        }
    }
}

private struct DownloadRow: View {
    let download: BrowserViewModel.DownloadItem
    let appearance: BrowserSidebarAppearance
    let revealAction: () -> Void
    let dismissAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(download.filename)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(appearance.primary)

                    statusView
                }

                Spacer(minLength: 0)

                VStack(spacing: 8) {
                    if case .finished = download.state {
                        Button(action: revealAction) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 28, height: 28)
                                .foregroundStyle(appearance.primary)
                        }
                        .buttonStyle(.plain)
                        .liquidGlassBackground(tint: appearance.controlTint, cornerRadius: 14, includeShadow: false)
                    }

                    Button(action: dismissAction) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 24, height: 24)
                            .foregroundStyle(appearance.primary.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .liquidGlassBackground(tint: appearance.controlTint.opacity(0.9), cornerRadius: 12, includeShadow: false)
                }
            }
        }
        .padding(14)
        .liquidGlassBackground(tint: appearance.controlTint.opacity(0.55), cornerRadius: 16, includeShadow: false)
    }

    @ViewBuilder
    private var statusView: some View {
        switch download.state {
        case .preparing:
            Text("Preparing…")
                .font(.caption)
                .foregroundStyle(appearance.secondary)
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 6) {
                if let progress {
                    ProgressView(value: progress, total: 1)
                        .progressViewStyle(.linear)
                        .tint(Color.browserAccent)
                    Text("\(Int(progress * 100))% complete")
                        .font(.caption2)
                        .foregroundStyle(appearance.secondary)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(Color.browserAccent)
                    Text("Downloading…")
                        .font(.caption2)
                        .foregroundStyle(appearance.secondary)
                }
            }
        case .finished(let url):
            Text("Saved to \(url.deletingLastPathComponent().lastPathComponent)")
                .font(.caption2)
                .foregroundStyle(appearance.secondary)
        case .failed(let message):
            Text(message)
                .font(.caption2)
                .foregroundStyle(Color.red.opacity(0.8))
        }
    }
}

#if os(macOS)
private struct MacAddressTextField: NSViewRepresentable {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var placeholder: String
    var onSubmit: () -> Void
    var onArrowDown: () -> Bool
    var onArrowUp: () -> Bool
    var onCancel: () -> Void
    var onFocusChange: (Bool) -> Void
    let controller: AddressFieldController

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        configure(textField)
        textField.delegate = context.coordinator
        textField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textField.stringValue = text
        context.coordinator.parent = self
        controller.textField = textField
        controller.focusIfNeeded()
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        context.coordinator.parent = self
        configure(nsView)
        controller.textField = nsView

        if isFocused.wrappedValue {
            controller.focusIfNeeded()
        } else {
            controller.blur()
        }
    }

    private func configure(_ textField: NSTextField) {
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.placeholderString = placeholder
        textField.usesSingleLineMode = true
        textField.maximumNumberOfLines = 1
        textField.lineBreakMode = .byTruncatingTail
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: MacAddressTextField

        init(parent: MacAddressTextField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            parent.isFocused.wrappedValue = true
            parent.onFocusChange(true)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            parent.onFocusChange(false)
            parent.isFocused.wrappedValue = false
            parent.controller.blur()
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            if parent.text != field.stringValue {
                parent.text = field.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)):
                return parent.onArrowDown()
            case #selector(NSResponder.moveUp(_:)):
                return parent.onArrowUp()
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }
    }
}

@MainActor
final class AddressFieldController: ObservableObject {
    weak var textField: NSTextField? {
        didSet {
            focusIfNeeded()
        }
    }

    private var pendingFocus = false

    func focus() {
        guard let textField else {
            pendingFocus = true
            return
        }

        guard let window = textField.window else {
            pendingFocus = true
            DispatchQueue.main.async { [weak self] in
                self?.focus()
            }
            return
        }

        pendingFocus = false

        if window.firstResponder !== textField.currentEditor() {
            window.makeFirstResponder(textField)
        }

        DispatchQueue.main.async {
            if let editor = textField.currentEditor() {
                editor.selectAll(nil)
            } else {
                textField.selectText(nil)
            }
        }
    }

    func focusIfNeeded() {
        if pendingFocus {
            focus()
        }
    }

    func blur() {
        guard let textField,
              let window = textField.window,
              window.firstResponder === textField.currentEditor() else { return }
        window.makeFirstResponder(nil)
    }
}
#endif

