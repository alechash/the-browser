import SwiftUI

struct DefaultHomeView: View {
    @ObservedObject var settings: BrowserSettings
    let onSubmitSearch: (String) -> Void
    let onOpenURL: (URL) -> Void
    let onOpenNewTab: () -> Void
    let onOpenSettings: () -> Void

    @State private var searchQuery = ""
    @FocusState private var isSearchFieldFocused: Bool
    @StateObject private var weatherProvider = HomeWeatherProvider()
    @State private var hasRequestedWeather = false

    private let backgroundGradient = LinearGradient(
        gradient: Gradient(colors: [
            Color.blue.opacity(0.35),
            Color.purple.opacity(0.25),
            Color.black.opacity(0.65)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        ZStack(alignment: .top) {
            backgroundLayer

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 32) {
                    headerSection
                    searchSection
                    weatherSection
                    quickAccessSection
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 48)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.browserBackground)
        .onAppear {
            guard !hasRequestedWeather else { return }
            hasRequestedWeather = true
            weatherProvider.refresh()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(greeting)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.85))

            Text("Ready to find something great?")
                .font(.system(size: 42, weight: .black, design: .rounded))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.leading)

            Text("Search the web, check the weather, or jump straight into a favourite spot.")
                .font(.callout)
                .foregroundStyle(Color.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchSection: some View {
        SearchCardView(
            engineName: settings.defaultSearchEngine.displayName,
            searchQuery: $searchQuery,
            isSearchFieldFocused: $isSearchFieldFocused,
            suggestions: trendingSearches,
            submitSearch: submitSearch,
            onSuggestion: onSubmitSearch
        )
    }

    @ViewBuilder
    private var weatherSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Right now", systemImage: "cloud.sun")
                    .labelStyle(.titleAndIcon)
                    .font(.headline)
                    .foregroundStyle(Color.white.opacity(0.88))

                Spacer()

                if weatherProvider.isLoading {
                    ProgressView()
                        .tint(Color.browserAccent)
                }
            }

            if let summary = weatherProvider.summary {
                WeatherSnapshotView(summary: summary)
            } else if let message = weatherProvider.statusMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.7))
            } else if !weatherProvider.isLoading {
                Text("Allow location access to show the local forecast.")
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        }
        .padding(28)
        .liquidGlassBackground(tint: Color.cyan.opacity(0.18), cornerRadius: 28)
    }

    private var quickAccessSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick access")
                .font(.headline)
                .foregroundStyle(Color.white.opacity(0.85))

            Text("A few handy places and actions to get you started.")
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.65))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 2), spacing: 16) {
                ForEach(quickLinks) { link in
                    Button {
                        perform(link.action)
                    } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: link.symbol)
                                .font(.title2)
                                .foregroundStyle(Color.browserAccent)

                            Text(link.title)
                                .font(.headline)
                                .foregroundStyle(Color.white)

                            if let detail = link.detail {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(Color.white.opacity(0.7))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.white.opacity(0.07))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(28)
        .liquidGlassBackground(tint: Color.white.opacity(0.08), cornerRadius: 28)
    }

    private var trendingSearches: [String] {
        let base = settings.defaultSearchEngine.displayName
        return [
            "Latest on \(base) news",
            "Weather this weekend",
            "New recipes to try"
        ]
    }

    private var quickLinks: [QuickLink] {
        [
            .init(
                title: "Open a new tab",
                symbol: "square.2.stack.3d",
                detail: "Start fresh with a blank page",
                action: .newTab
            ),
            .init(
                title: "Today's headlines",
                symbol: "newspaper",
                detail: "Top stories from around the world",
                action: .search("today's news")
            ),
            .init(
                title: "Jump to GitHub",
                symbol: "chevron.left.forwardslash.chevron.right",
                detail: "Pick up where you left off in code",
                action: .open(URL(string: "https://github.com")!)
            ),
            .init(
                title: "Browser settings",
                symbol: "slider.horizontal.3",
                detail: "Adjust your experience",
                action: .settings
            )
        ]
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Hello"
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            Circle()
                .fill(Color.purple.opacity(0.15))
                .frame(width: 360, height: 360)
                .blur(radius: 120)
                .offset(x: -220, y: -240)

            Circle()
                .fill(Color.blue.opacity(0.18))
                .frame(width: 320, height: 320)
                .blur(radius: 110)
                .offset(x: 220, y: -180)

            Circle()
                .fill(Color.cyan.opacity(0.16))
                .frame(width: 420, height: 420)
                .blur(radius: 140)
                .offset(x: 0, y: 320)
        }
    }

    private func submitSearch() {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmitSearch(trimmed)
        searchQuery = ""
    }

    private func perform(_ action: QuickLink.Action) {
        switch action {
        case .newTab:
            onOpenNewTab()
        case .search(let query):
            onSubmitSearch(query)
        case .open(let url):
            onOpenURL(url)
        case .settings:
            onOpenSettings()
        }
    }
}

private struct SearchCardView: View {
    let engineName: String
    @Binding var searchQuery: String
    let isSearchFieldFocused: FocusState<Bool>.Binding
    let suggestions: [String]
    let submitSearch: () -> Void
    let onSuggestion: (String) -> Void

    private var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Search with \(engineName)")
                .font(.headline)
                .foregroundStyle(Color.white.opacity(0.85))

            HStack(spacing: 16) {
                Image(systemName: "magnifyingglass")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.65))

                TextField("Search the web", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Color.white)
                    .disableAutocorrection(true)
                    .focused(isSearchFieldFocused)
                    .onSubmit(submitSearch)
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                #endif

                Button(action: submitSearch) {
                    Label("Go", systemImage: "arrow.up.right.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.plain)
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.browserAccent, Color.white)
                .disabled(trimmedQuery.isEmpty)
                .opacity(trimmedQuery.isEmpty ? 0.4 : 1)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )

            if !suggestions.isEmpty {
                HStack(spacing: 10) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            onSuggestion(suggestion)
                        } label: {
                            Text(suggestion)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(28)
        .liquidGlassBackground(tint: Color.blue.opacity(0.18), cornerRadius: 28)
    }
}

private struct WeatherSnapshotView: View {
    let summary: HomeWeatherProvider.WeatherSummary

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: summary.symbolName)
                .font(.system(size: 46, weight: .medium, design: .rounded))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.browserAccent, Color.white)
                .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 6) {
                Text(summary.temperatureText)
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)

                Text(summary.conditionText)
                    .font(.callout)
                    .foregroundStyle(Color.white.opacity(0.78))

                if let location = summary.locationName {
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.65))
                }
            }

            Spacer()
        }
    }
}

private struct QuickLink: Identifiable {
    enum Action {
        case newTab
        case search(String)
        case open(URL)
        case settings
    }

    let id = UUID()
    let title: String
    let symbol: String
    let detail: String?
    let action: Action
}

#Preview {
    DefaultHomeView(
        settings: BrowserSettings(),
        onSubmitSearch: { _ in },
        onOpenURL: { _ in },
        onOpenNewTab: {},
        onOpenSettings: {}
    )
}
