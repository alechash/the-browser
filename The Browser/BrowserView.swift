import SwiftUI
import Combine
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
                if let spaceID = viewModel.currentSpaceID {
                    SpaceWorkspaceView(viewModel: viewModel, spaceID: spaceID, appearance: viewModel.sidebarAppearance)
                } else if currentTabKind == .history {
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
                #if os(macOS)
                BrowserSidebar(
                    viewModel: viewModel,
                    appearance: viewModel.sidebarAppearance,
                    isAddressFocused: $isAddressFocused,
                    isShowingSettings: $isShowingSettings,
                    enterFullscreen: { withAnimation { isWebContentFullscreen = true } }
                    , addressFieldController: addressFieldController
                )
                .frame(width: sidebarWidth)
                .transition(.move(edge: .leading).combined(with: .opacity))
                #else
                BrowserSidebar(
                    viewModel: viewModel,
                    appearance: viewModel.sidebarAppearance,
                    isAddressFocused: $isAddressFocused,
                    isShowingSettings: $isShowingSettings,
                    enterFullscreen: { withAnimation { isWebContentFullscreen = true } }
                )
                .frame(width: sidebarWidth)
                .transition(.move(edge: .leading).combined(with: .opacity))
                #endif
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
    @State private var isCreatingSpace = false
    @State private var newSpaceName: String = ""
    @FocusState private var isSpaceCreationFieldFocused: Bool

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
#if os(macOS)
                    addressFieldController.blur()
#endif
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
        VStack(alignment: .leading, spacing: 20) {
            spacesSection
            tabsSection
        }
    }

    private var spacesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Spaces")
                    .font(.caption)
                    .foregroundStyle(appearance.secondary)
                Spacer()
                Button(action: toggleSpaceCreation) {
                    Image(systemName: isCreatingSpace ? "xmark" : "plus.folder")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(appearance.primary)
                }
                .buttonStyle(.plain)
                .liquidGlassBackground(tint: appearance.controlTint, cornerRadius: 14, includeShadow: false)
#if os(macOS)
                .help(isCreatingSpace ? "Cancel" : "Create Space")
#endif
            }

            if isCreatingSpace {
                SpaceCreationRow(
                    name: $newSpaceName,
                    appearance: appearance,
                    isFieldFocused: $isSpaceCreationFieldFocused,
                    commitAction: commitNewSpace,
                    cancelAction: cancelNewSpace
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if viewModel.spaces.isEmpty {
                Text("Spaces are where ideas get room to breathe. Create one to start collecting inspiration.")
                    .font(.footnote)
                    .foregroundStyle(appearance.secondary)
                    .padding(.horizontal, 6)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.spaces) { space in
                        SpaceRow(
                            space: space,
                            isSelected: viewModel.isSpaceSelected(space.id),
                            appearance: appearance,
                            selectAction: { viewModel.selectSpace(space.id) },
                            pinAction: { viewModel.pinCurrentTab(in: space.id) },
                            deleteAction: { viewModel.deleteSpace(space.id) }
                        )
                    }
                }
            }
        }
    }

    private func toggleSpaceCreation() {
        if isCreatingSpace {
            cancelNewSpace()
        } else {
            newSpaceName = ""
            withAnimation(.easeInOut(duration: 0.2)) {
                isCreatingSpace = true
            }
            DispatchQueue.main.async {
                isSpaceCreationFieldFocused = true
            }
        }
    }

    private func commitNewSpace() {
        let trimmed = newSpaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        viewModel.createSpace(title: trimmed.isEmpty ? "New Space" : trimmed)
        newSpaceName = ""
        isSpaceCreationFieldFocused = false
        withAnimation(.easeInOut(duration: 0.2)) {
            isCreatingSpace = false
        }
    }

    private func cancelNewSpace() {
        newSpaceName = ""
        isSpaceCreationFieldFocused = false
        withAnimation(.easeInOut(duration: 0.2)) {
            isCreatingSpace = false
        }
    }

    private var tabsSection: some View {
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
                            faviconURL: viewModel.faviconURL(for: tab),
                            isInSplitView: viewModel.isTabInSplitView(tab.id),
                            canShowInSplitView: viewModel.canShowTabInSplitView(tab.id),
                            toggleSplitAction: { viewModel.toggleSplitView(for: tab.id) },
                            splitOrientation: viewModel.splitViewOrientation,
                            isPoppedOut: viewModel.isTabPoppedOut(tab.id),
                            canPopOut: viewModel.canPopOutTab(tab.id),
                            togglePopOutAction: { viewModel.togglePopOut(for: tab.id) }
                        )
                        .contextMenu {
                            spacesContextMenu(for: tab)
                        }
#else
                        TabRow(
                            tab: tab,
                            isSelected: tab.id == viewModel.selectedTabID,
                            appearance: appearance,
                            selectAction: { viewModel.selectTab(tab.id) },
                            closeAction: { viewModel.closeTab(tab.id) },
                            faviconURL: viewModel.faviconURL(for: tab),
                            isInSplitView: viewModel.isTabInSplitView(tab.id),
                            canShowInSplitView: viewModel.canShowTabInSplitView(tab.id),
                            toggleSplitAction: { viewModel.toggleSplitView(for: tab.id) },
                            splitOrientation: viewModel.splitViewOrientation
                        )
                        .contextMenu {
                            spacesContextMenu(for: tab)
                        }
#endif
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func spacesContextMenu(for tab: BrowserViewModel.TabState) -> some View {
        if tab.kind != .web {
            Label("Only web tabs can be saved", systemImage: "exclamationmark.triangle")
                .disabled(true)
        } else if viewModel.spaces.isEmpty {
            Label("Create a space to save tabs", systemImage: "folder.badge.plus")
                .disabled(true)
        } else {
            Section("Save Tab to Space") {
                ForEach(viewModel.spaces) { space in
                    Button {
                        viewModel.saveTab(tab.id, to: space.id)
                    } label: {
                        Label(space.name, systemImage: "folder")
                    }
                }
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

private struct SpaceCreationRow: View {
    @Binding var name: String
    let appearance: BrowserSidebarAppearance
    var isFieldFocused: FocusState<Bool>.Binding
    let commitAction: () -> Void
    let cancelAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New Space")
                .font(.caption)
                .foregroundStyle(appearance.secondary)

            HStack(spacing: 10) {
                TextField("Creative Hub", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused(isFieldFocused)
                    .onSubmit(commitAction)

                Button(action: commitAction) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(appearance.primary)
                }
                .buttonStyle(.plain)
                .liquidGlassBackground(tint: appearance.controlTint.opacity(0.95), cornerRadius: 14, includeShadow: false)

                Button(action: cancelAction) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(appearance.primary)
                }
                .buttonStyle(.plain)
                .liquidGlassBackground(tint: appearance.controlTint.opacity(0.65), cornerRadius: 14, includeShadow: false)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(appearance.controlTint.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(appearance.primary.opacity(0.15), lineWidth: 1)
        )
    }
}

private struct SpaceRow: View {
    let space: BrowserViewModel.Space
    let isSelected: Bool
    let appearance: BrowserSidebarAppearance
    let selectAction: () -> Void
    let pinAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: resolvedIconName)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 32, height: 32)
                .foregroundStyle(appearance.primary)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(appearance.controlTint.opacity(isSelected ? 1 : 0.9))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(space.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(appearance.primary)

                Text(summaryText)
                    .font(.caption2)
                    .foregroundStyle(appearance.secondary)
                    .lineLimit(2)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: pinAction) {
                    Image(systemName: "pin")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .foregroundStyle(appearance.primary)
                }
                .buttonStyle(.plain)
                .liquidGlassBackground(tint: appearance.controlTint.opacity(0.85), cornerRadius: 10, includeShadow: false)
#if os(macOS)
                .help("Pin Current Tab to Space")
#endif

                Button(role: .destructive, action: deleteAction) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .foregroundStyle(appearance.primary)
                }
                .buttonStyle(.plain)
                .liquidGlassBackground(tint: appearance.controlTint.opacity(0.75), cornerRadius: 10, includeShadow: false)
#if os(macOS)
                .help("Delete Space")
#endif
            }
            .opacity(space.isEmpty ? 0.85 : 1)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassBackground(tint: appearance.controlTint.opacity(isSelected ? 0.95 : 0.72), cornerRadius: 16, includeShadow: false)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(isSelected ? 1 : 0.92)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(appearance.primary.opacity(isSelected ? 0.4 : 0), lineWidth: 1.5)
        )
        .onTapGesture(perform: selectAction)
    }

    private var summaryText: String {
        var parts: [String] = []
        if !space.pinnedTabs.isEmpty {
            parts.append("\(space.pinnedTabs.count) pinned tab\(space.pinnedTabs.count == 1 ? "" : "s")")
        }
        if !space.savedTabs.isEmpty {
            parts.append("\(space.savedTabs.count) saved tab\(space.savedTabs.count == 1 ? "" : "s")")
        }
        if !space.notes.isEmpty {
            parts.append("\(space.notes.count) note\(space.notes.count == 1 ? "" : "s")")
        }
        if !space.links.isEmpty {
            parts.append("\(space.links.count) link\(space.links.count == 1 ? "" : "s")")
        }
        if !space.images.isEmpty {
            parts.append("\(space.images.count) image\(space.images.count == 1 ? "" : "s")")
        }
        if parts.isEmpty {
            return "An open canvas for creativity"
        }
        return parts.joined(separator: " • ")
    }

    private var resolvedIconName: String {
        let trimmed = space.iconName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "folder" : trimmed
    }
}

private struct SpaceWorkspaceView: View {
    @ObservedObject var viewModel: BrowserViewModel
    let spaceID: UUID
    let appearance: BrowserSidebarAppearance
    @State private var noteDraft: String = ""
    @State private var linkTitle: String = ""
    @State private var linkURL: String = ""
    @State private var imageURL: String = ""
    @State private var imageCaption: String = ""
    @FocusState private var isNoteFieldFocused: Bool
    @FocusState private var isLinkURLFocused: Bool
    @FocusState private var isImageURLFocused: Bool

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 320, maximum: 420), spacing: 24)]
    }

    private var heroColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 14)]
    }

    private var space: BrowserViewModel.Space? {
        viewModel.space(with: spaceID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header
                if let space {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                        pinnedTabsCard(space)
                        savedTabsCard(space)
                        notesCard(space)
                        linksCard(space)
                        imagesCard(space)
                    }
                } else {
                    spaceUnavailable
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 48)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color.browserBackground)
    }

    private var header: some View {
        Group {
            if let space {
                VStack(alignment: .leading, spacing: 28) {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        appearance.controlTint.opacity(0.95),
                                        appearance.controlTint.opacity(0.55)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 34, style: .continuous)
                                    .stroke(appearance.primary.opacity(0.12), lineWidth: 1.2)
                            )

                        VStack(alignment: .leading, spacing: 24) {
                            HStack(alignment: .top, spacing: 22) {
                                iconPicker(for: space)

                                VStack(alignment: .leading, spacing: 10) {
                                    TextField(
                                        "Space Name",
                                        text: Binding(
                                            get: { space.name },
                                            set: { viewModel.renameSpace(spaceID, to: $0) }
                                        )
                                    )
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .textFieldStyle(.plain)
                                    .foregroundStyle(appearance.primary)

                                    HStack(spacing: 10) {
                                        SpaceBadge(text: formatted(date: space.createdAt), icon: "calendar", appearance: appearance)
                                        if space.isEmpty {
                                            SpaceBadge(text: "Fresh Canvas", icon: "sparkles", appearance: appearance)
                                        }
                                    }
                                }

                                Spacer(minLength: 0)

                                Menu {
                                    Button(role: .destructive) {
                                        viewModel.deleteSpace(spaceID)
                                    } label: {
                                        Label("Delete Space", systemImage: "trash")
                                    }
                                } label: {
                                    Label("Manage Space", systemImage: "ellipsis.circle")
                                        .labelStyle(.iconOnly)
                                        .font(.system(size: 24, weight: .semibold))
                                        .frame(width: 52, height: 52)
                                        .foregroundStyle(appearance.primary)
                                        .background(
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .fill(Color.white.opacity(0.18))
                                        )
                                }
                                .menuStyle(.borderlessButton)
#if os(macOS)
                                .help("Space Actions")
#endif
                            }

                            metricRow(for: space)

                            heroActions(for: space)
                        }
                        .padding(32)
                    }
                    .shadow(color: appearance.primary.opacity(0.14), radius: 24, x: 0, y: 18)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Icon (SF Symbol)")
                            .font(.caption)
                            .foregroundStyle(appearance.secondary.opacity(0.85))

                        TextField(
                            "folder",
                            text: Binding(
                                get: { space.iconName },
                                set: { viewModel.updateSpaceIcon(spaceID, to: $0) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                    }
                }
            } else {
                spaceUnavailable
            }
        }
    }

    private var spaceUnavailable: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Space Unavailable")
                .font(.title2.weight(.semibold))
                .foregroundStyle(appearance.primary)
            Text("This space could not be found. It may have been removed or is still loading.")
                .font(.callout)
                .foregroundStyle(appearance.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(appearance.controlTint.opacity(0.6))
        )
    }

    private func pinnedTabsCard(_ space: BrowserViewModel.Space) -> some View {
        SpaceCard(title: "Pinned Tabs", icon: "pin", appearance: appearance) {
            if space.pinnedTabs.isEmpty {
                SpaceEmptyState(
                    message: "No pinned tabs yet. Pin pages you want quick access to."
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(space.pinnedTabs) { pinned in
                        SpaceItemContainer(appearance: appearance) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(pinned.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(appearance.primary)
                                if let url = pinned.url {
                                    Text(url.absoluteString)
                                        .font(.caption2)
                                        .foregroundStyle(appearance.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }

                            Spacer(minLength: 12)

                            VStack(spacing: 8) {
                                Button("Open") {
                                    viewModel.openPinnedTab(spaceID: spaceID, pinnedID: pinned.id)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(pinned.url == nil)

                                Button(role: .destructive) {
                                    viewModel.removePinnedTab(in: spaceID, pinnedID: pinned.id)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }

            Divider().padding(.vertical, 4)

            Button {
                viewModel.pinCurrentTab(in: spaceID)
            } label: {
                Label("Pin Current Tab", systemImage: "pin")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(!viewModel.currentTabExists)
        }
    }

    private func heroActions(for space: BrowserViewModel.Space) -> some View {
        LazyVGrid(columns: heroColumns, alignment: .leading, spacing: 14) {
            SpaceHeroAction(
                title: "Pin Current Tab",
                subtitle: "Keep essentials a tap away",
                icon: "pin",
                tint: Color.blue,
                appearance: appearance,
                isDisabled: !viewModel.currentTabExists,
                action: { viewModel.pinCurrentTab(in: spaceID) }
            )

            SpaceHeroAction(
                title: "Save for Later",
                subtitle: "Archive the current page",
                icon: "bookmark",
                tint: Color.purple,
                appearance: appearance,
                isDisabled: !viewModel.currentTabExists,
                action: { viewModel.saveCurrentTab(to: spaceID) }
            )

            SpaceHeroAction(
                title: "Capture a Note",
                subtitle: "Jot thoughts before they vanish",
                icon: "square.and.pencil",
                tint: Color.orange,
                appearance: appearance,
                isDisabled: false,
                action: primeNoteComposer
            )

            SpaceHeroAction(
                title: "Save a Link",
                subtitle: "Drop in a quick reference",
                icon: "link.badge.plus",
                tint: Color.green,
                appearance: appearance,
                isDisabled: false,
                action: primeLinkComposer
            )

            SpaceHeroAction(
                title: "Add Image",
                subtitle: "Collect visual inspiration",
                icon: "photo.on.rectangle.angled",
                tint: Color.pink,
                appearance: appearance,
                isDisabled: false,
                action: primeImageComposer
            )
        }
    }

    private func primeNoteComposer() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isNoteFieldFocused = true
        }
    }

    private func primeLinkComposer() {
        if linkURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let currentURL = viewModel.currentURL {
            linkURL = currentURL.absoluteString
        }
        if linkTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let candidate = viewModel.currentTabTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty {
                linkTitle = candidate
            } else if let host = viewModel.currentURL?.host {
                linkTitle = host
            }
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            isLinkURLFocused = true
        }
    }

    private func primeImageComposer() {
        if imageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let currentURL = viewModel.currentURL {
            imageURL = currentURL.absoluteString
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            isImageURLFocused = true
        }
    }

    private func savedTabsCard(_ space: BrowserViewModel.Space) -> some View {
        SpaceCard(title: "Saved Tabs", icon: "bookmark", appearance: appearance) {
            if space.savedTabs.isEmpty {
                SpaceEmptyState(message: "Capture tabs you want to revisit without keeping them open.")
            } else {
                VStack(spacing: 12) {
                    ForEach(space.savedTabs) { saved in
                        SpaceItemContainer(appearance: appearance) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    if let host = host(from: saved.url) {
                                        SpaceBadge(text: host, icon: "globe", appearance: appearance)
                                    }
                                    SpaceBadge(text: "Saved Tab", icon: "bookmark.fill", appearance: appearance)
                                }

                                Text(saved.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(appearance.primary)
                                if let url = saved.url {
                                    Text(url.absoluteString)
                                        .font(.caption2)
                                        .foregroundStyle(appearance.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Text("Saved \(formatted(date: saved.capturedAt))")
                                    .font(.caption2)
                                    .foregroundStyle(appearance.secondary.opacity(0.85))
                            }

                            Spacer(minLength: 12)

                            VStack(spacing: 8) {
                                Button("Open") {
                                    viewModel.openSavedTab(spaceID: spaceID, savedID: saved.id)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(saved.url == nil)

                                Button(role: .destructive) {
                                    viewModel.removeSavedTab(in: spaceID, savedID: saved.id)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }

            Divider().padding(.vertical, 4)

            Button {
                viewModel.saveCurrentTab(to: spaceID)
            } label: {
                Label("Save Current Tab", systemImage: "bookmark")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(!viewModel.currentTabExists)
        }
    }

    private func notesCard(_ space: BrowserViewModel.Space) -> some View {
        SpaceCard(title: "Notes", icon: "highlighter", appearance: appearance) {
            if space.notes.isEmpty {
                SpaceEmptyState(message: "Capture sparks, next steps, or quick reminders.")
            } else {
                VStack(spacing: 12) {
                    ForEach(space.notes) { note in
                        SpaceItemContainer(appearance: appearance) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(note.text)
                                    .font(.body)
                                    .foregroundStyle(appearance.primary)
                                    .multilineTextAlignment(.leading)
                                Text(formatted(date: note.createdAt))
                                    .font(.caption2)
                                    .foregroundStyle(appearance.secondary.opacity(0.85))
                            }

                            Button(role: .destructive) {
                                viewModel.removeNote(in: spaceID, noteID: note.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            Divider().padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 10) {
                Text("New Note")
                    .font(.caption)
                    .foregroundStyle(appearance.secondary.opacity(0.85))

                TextEditor(text: $noteDraft)
                    .frame(minHeight: 90)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(appearance.controlTint.opacity(0.75))
                    )
                    .focused($isNoteFieldFocused)

                Button {
                    viewModel.addNote(to: spaceID, text: noteDraft)
                    noteDraft = ""
                    isNoteFieldFocused = false
                } label: {
                    Label("Save Note", systemImage: "square.and.arrow.down")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func linksCard(_ space: BrowserViewModel.Space) -> some View {
        SpaceCard(title: "Links", icon: "link", appearance: appearance) {
            if space.links.isEmpty {
                SpaceEmptyState(message: "Save references, reading lists, and resources.")
            } else {
                VStack(spacing: 12) {
                    ForEach(space.links) { link in
                        SpaceItemContainer(appearance: appearance) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    if let host = host(from: link.url) {
                                        SpaceBadge(text: host, icon: "link", appearance: appearance)
                                    }
                                    SpaceBadge(text: "Resource", icon: "book", appearance: appearance)
                                }

                                Text(link.displayTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(appearance.primary)
                                if let url = link.url {
                                    Text(url.absoluteString)
                                        .font(.caption2)
                                        .foregroundStyle(appearance.secondary)
                                        .lineLimit(2)
                                        .truncationMode(.middle)
                                }
                                Text("Saved \(formatted(date: link.createdAt))")
                                    .font(.caption2)
                                    .foregroundStyle(appearance.secondary.opacity(0.85))
                            }

                            Spacer(minLength: 12)

                            VStack(spacing: 8) {
                                Button("Open") {
                                    viewModel.openLink(spaceID: spaceID, linkID: link.id)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(link.url == nil)

                                Button(role: .destructive) {
                                    viewModel.removeLink(in: spaceID, linkID: link.id)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }

            Divider().padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 10) {
                Text("New Link")
                    .font(.caption)
                    .foregroundStyle(appearance.secondary.opacity(0.85))

                TextField("Title", text: $linkTitle)
                    .textFieldStyle(.roundedBorder)

                TextField("https://example.com", text: $linkURL)
                    .textFieldStyle(.roundedBorder)
                    .focused($isLinkURLFocused)

                Button {
                    viewModel.addLink(to: spaceID, title: linkTitle, urlString: linkURL)
                    linkTitle = ""
                    linkURL = ""
                    isLinkURLFocused = false
                } label: {
                    Label("Save Link", systemImage: "link")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(linkURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func imagesCard(_ space: BrowserViewModel.Space) -> some View {
        SpaceCard(title: "Images", icon: "photo.on.rectangle", appearance: appearance) {
            if space.images.isEmpty {
                SpaceEmptyState(message: "Collect inspiration, mood boards, and reference art.")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                    ForEach(space.images) { image in
                        SpaceImageTile(
                            image: image,
                            appearance: appearance,
                            removeAction: { viewModel.removeImage(in: spaceID, imageID: image.id) }
                        )
                    }
                }
            }

            Divider().padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 10) {
                Text("Add Image")
                    .font(.caption)
                    .foregroundStyle(appearance.secondary.opacity(0.85))

                TextField("Image URL", text: $imageURL)
                    .textFieldStyle(.roundedBorder)
                    .focused($isImageURLFocused)

                TextField("Caption", text: $imageCaption)
                    .textFieldStyle(.roundedBorder)

                Button {
                    viewModel.addImage(to: spaceID, urlString: imageURL, caption: imageCaption)
                    imageURL = ""
                    imageCaption = ""
                    isImageURLFocused = false
                } label: {
                    Label("Save Image", systemImage: "photo.fill.on.rectangle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(imageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func metricRow(for space: BrowserViewModel.Space) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                metricChip(title: "Pinned", value: space.pinnedTabs.count, systemIcon: "pin")
                metricChip(title: "Saved", value: space.savedTabs.count, systemIcon: "bookmark")
                metricChip(title: "Notes", value: space.notes.count, systemIcon: "note.text")
                metricChip(title: "Links", value: space.links.count, systemIcon: "link")
                metricChip(title: "Images", value: space.images.count, systemIcon: "photo")
            }
        }
    }

    private func host(from url: URL?) -> String? {
        guard let rawHost = url?.host, !rawHost.isEmpty else { return nil }
        if rawHost.lowercased().hasPrefix("www.") {
            return String(rawHost.dropFirst(4))
        }
        return rawHost
    }

    private func metricChip(title: String, value: Int, systemIcon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemIcon)
                .font(.system(size: 12, weight: .semibold))
            Text("\(value)")
                .font(.subheadline.weight(.semibold))
            Text(title)
                .font(.footnote)
        }
        .foregroundStyle(appearance.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(appearance.controlTint.opacity(0.85))
        )
    }

    @ViewBuilder
    private func iconPicker(for space: BrowserViewModel.Space) -> some View {
        let iconName = resolvedIconName(space.iconName)
        Menu {
            ForEach(iconChoices, id: \.self) { option in
                Button {
                    viewModel.updateSpaceIcon(spaceID, to: option)
                } label: {
                    Label(iconDisplayName(for: option), systemImage: option)
                }
            }
        } label: {
            Image(systemName: iconName)
                .font(.system(size: 32, weight: .semibold))
                .frame(width: 72, height: 72)
                .foregroundStyle(appearance.primary)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(appearance.controlTint.opacity(0.95))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(appearance.primary.opacity(0.18), lineWidth: 1.4)
                )
        }
        .menuStyle(.borderlessButton)
#if os(macOS)
        .help("Choose Icon")
#endif
    }

    private var iconChoices: [String] {
        [
            "folder",
            "sparkles",
            "lightbulb",
            "paintpalette",
            "bookmark",
            "camera",
            "music.note",
            "leaf",
            "heart",
            "globe",
            "brain.head.profile"
        ]
    }

    private func iconDisplayName(for symbol: String) -> String {
        symbol.replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private func resolvedIconName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "folder" : trimmed
    }

    private func formatted(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct SpaceBadge: View {
    let text: String
    let icon: String?
    let appearance: BrowserSidebarAppearance

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(appearance.controlTint.opacity(0.4))
        )
        .foregroundStyle(appearance.primary)
    }
}

private struct SpaceHeroAction: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let appearance: BrowserSidebarAppearance
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(appearance.primary.opacity(0.15))
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(Color.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.95),
                                tint.opacity(0.65)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(appearance.primary.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: tint.opacity(0.25), radius: 16, x: 0, y: 12)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.35 : 1)
    }
}

private struct SpaceCard<Content: View>: View {
    let title: String
    let icon: String
    let appearance: BrowserSidebarAppearance
    let content: Content

    init(title: String, icon: String, appearance: BrowserSidebarAppearance, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.appearance = appearance
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(appearance.primary)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        appearance.controlTint.opacity(1),
                                        appearance.controlTint.opacity(0.7)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(appearance.primary)
            }

            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            appearance.controlTint.opacity(0.78),
                            appearance.controlTint.opacity(0.52)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(appearance.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: appearance.primary.opacity(0.08), radius: 16, x: 0, y: 10)
    }
}

private struct SpaceItemContainer<Content: View>: View {
    let appearance: BrowserSidebarAppearance
    let content: Content

    init(appearance: BrowserSidebarAppearance, @ViewBuilder content: () -> Content) {
        self.appearance = appearance
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            appearance.controlTint.opacity(0.98),
                            appearance.controlTint.opacity(0.75)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(appearance.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct SpaceEmptyState: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.secondary)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

private struct SpaceImageTile: View {
    let image: BrowserViewModel.Space.ImageResource
    let appearance: BrowserSidebarAppearance
    let removeAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(appearance.controlTint.opacity(0.9))
                    .overlay(
                        Group {
                            if let url = image.url {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let loaded):
                                        loaded
                                            .resizable()
                                            .scaledToFill()
                                    case .empty:
                                        progressView
                                    case .failure:
                                        placeholder
                                    @unknown default:
                                        placeholder
                                    }
                                }
                                .clipped()
                            } else {
                                placeholder
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    )
                    .frame(height: 140)

                Button(role: .destructive, action: removeAction) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(6)
                }
#if os(macOS)
                .buttonStyle(.borderless)
#else
                .buttonStyle(.plain)
#endif
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.35))
                )
                .foregroundStyle(Color.white)
                .padding(8)
            }

            Text(image.displayCaption)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(appearance.primary)

            if let url = image.url {
                Text(url.absoluteString)
                    .font(.caption2)
                    .foregroundStyle(appearance.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.12))
            Image(systemName: "photo")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.8))
        }
    }

    @ViewBuilder
    private var progressView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.1))
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Color.white.opacity(0.8))
        }
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
    let faviconURL: URL?
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

#if os(macOS)
                    FaviconCloseButton(faviconURL: faviconURL, appearance: appearance, closeAction: closeAction)
#else
                    Button(action: closeAction) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 24, height: 24)
                            .foregroundStyle(appearance.primary)
                    }
                    .buttonStyle(.plain)
                    .opacity(0.7)
#endif
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

#if os(macOS)
private struct FaviconCloseButton: View {
    let faviconURL: URL?
    let appearance: BrowserSidebarAppearance
    let closeAction: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: closeAction) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(appearance.controlTint.opacity(isHovering ? 0.9 : 0.75))

                faviconContent
                    .frame(width: 18, height: 18)
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }

    @ViewBuilder
    private var faviconContent: some View {
        if isHovering || faviconURL == nil {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(appearance.primary)
        } else {
            AsyncImage(url: faviconURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                case .empty, .failure:
                    fallbackIcon()
                @unknown default:
                    fallbackIcon()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    @ViewBuilder
    private func fallbackIcon() -> some View {
        Image(systemName: "globe")
            .resizable()
            .scaledToFit()
            .foregroundStyle(appearance.primary)
            .padding(2)
    }
}
#endif

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

