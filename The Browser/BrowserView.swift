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

    private let sidebarWidth: CGFloat = 288

    init() {
        let settings = BrowserSettings()
        _settings = StateObject(wrappedValue: settings)
        _viewModel = StateObject(wrappedValue: BrowserViewModel(settings: settings))
    }

    @ViewBuilder
    private var contentView: some View {
        let tabIDs = viewModel.displayedTabIDs

        if tabIDs.isEmpty {
            if let selected = viewModel.selectedTabID, viewModel.isTabPoppedOut(selected) {
                PoppedOutPlaceholder(tabTitle: viewModel.tabState(for: selected)?.displayTitle ?? "Tab")
            } else if let selected = viewModel.selectedTabID {
                BrowserTabContentView(viewModel: viewModel, tabID: selected)
            } else {
                DefaultHomeView()
            }
        } else if tabIDs.count == 1, let tabID = tabIDs.first {
            BrowserTabContentView(viewModel: viewModel, tabID: tabID)
        } else {
            BrowserSplitStack(viewModel: viewModel, tabIDs: tabIDs, selectedTabID: viewModel.selectedTabID)
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            contentView
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

private struct BrowserSidebar: View {
    @ObservedObject var viewModel: BrowserViewModel
    let appearance: BrowserSidebarAppearance
    var isAddressFocused: FocusState<Bool>.Binding
    @Binding var isShowingSettings: Bool
    let enterFullscreen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            VStack(alignment: .leading, spacing: 14) {
                navigationControls
                addressField
            }

            divider

            tabList

            Spacer()

            HStack(spacing: 12) {
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

            TextField(
                "Search or enter website name",
                text: Binding(
                    get: { viewModel.currentAddressText },
                    set: { viewModel.updateAddressText($0) }
                )
            )
            .focused(isAddressFocused)
            .textFieldStyle(.plain)
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
            .liquidGlassBackground(tint: appearance.controlTint, cornerRadius: 16, includeShadow: false)
            .tint(appearance.primary)
            .onSubmit {
                viewModel.submitAddress()
                isAddressFocused.wrappedValue = false
            }
#if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .disableAutocorrection(true)
            .submitLabel(.go)
#endif
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(appearance.primary.opacity(0.12))
            .frame(height: 1)
            .padding(.vertical, 4)
    }

    private var tabList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tabs")
                    .font(.caption)
                    .foregroundStyle(appearance.secondary)
                Spacer()
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
                        TabRow(
                            tab: tab,
                            isSelected: tab.id == viewModel.selectedTabID,
                            isInSplitView: viewModel.isTabInSplitView(tab.id),
                            isPoppedOut: viewModel.isTabPoppedOut(tab.id),
                            appearance: appearance,
                            selectAction: { viewModel.selectTab(tab.id) },
                            closeAction: { viewModel.closeTab(tab.id) },
                            toggleSplitAction: { viewModel.toggleTabInSplitView(tab.id) },
#if os(macOS)
                            popOutAction: { viewModel.popOutTab(tab.id) },
                            reattachAction: { viewModel.reattachTab(tab.id) }
#else
                            popOutAction: nil,
                            reattachAction: nil
#endif
                        )
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
    let isInSplitView: Bool
    let isPoppedOut: Bool
    let appearance: BrowserSidebarAppearance
    let selectAction: () -> Void
    let closeAction: () -> Void
    let toggleSplitAction: () -> Void
    let popOutAction: (() -> Void)?
    let reattachAction: (() -> Void)?

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

            if isPoppedOut {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(appearance.secondary)
            } else if isInSplitView {
                Image(systemName: "square.split.2x1.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(appearance.secondary)
            }

            if tab.isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(appearance.primary)
            } else {
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
        .contextMenu {
            Button(isInSplitView ? "Remove from Split View" : "Add to Split View", action: toggleSplitAction)
#if os(macOS)
            if isPoppedOut, let reattachAction {
                Button("Reattach Tab", action: reattachAction)
            } else if let popOutAction {
                Button("Pop Out Tab", action: popOutAction)
            }
#endif
        }
    }
}

private struct BrowserSplitStack: View {
    @ObservedObject var viewModel: BrowserViewModel
    let tabIDs: [UUID]
    let selectedTabID: UUID?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabIDs.enumerated()), id: \.element) { index, tabID in
                BrowserTabPane(viewModel: viewModel, tabID: tabID, isSelected: tabID == selectedTabID)
                if index < tabIDs.count - 1 {
                    Divider()
                        .background(Color.black.opacity(0.12))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct BrowserTabPane: View {
    @ObservedObject var viewModel: BrowserViewModel
    let tabID: UUID
    let isSelected: Bool

    var body: some View {
        BrowserTabContentView(viewModel: viewModel, tabID: tabID)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 0)
                    .stroke(isSelected ? Color.browserAccent : Color.clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.selectTab(tabID)
            }
            .contextMenu {
                Button("Remove from Split View") {
                    viewModel.removeTabFromSplitView(tabID)
                }
#if os(macOS)
                if viewModel.isTabPoppedOut(tabID) {
                    Button("Reattach Tab") {
                        viewModel.reattachTab(tabID)
                    }
                } else {
                    Button("Pop Out Tab") {
                        viewModel.popOutTab(tabID)
                    }
                }
#endif
            }
    }
}

struct BrowserTabContentView: View {
    @ObservedObject var viewModel: BrowserViewModel
    let tabID: UUID

    var body: some View {
        Group {
            if let tab = viewModel.tabState(for: tabID) {
                switch tab.kind {
                case .nativeHome:
                    DefaultHomeView()
                case .web:
                    BrowserWebView(viewModel: viewModel, tabID: tabID)
                }
            } else {
                DefaultHomeView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.browserBackground)
    }
}

private struct PoppedOutPlaceholder: View {
    let tabTitle: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.up.right.square")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Color.browserAccent)

            Text("\(tabTitle) is open in a separate window")
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("Use the tab menu to reattach it to this workspace.")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

