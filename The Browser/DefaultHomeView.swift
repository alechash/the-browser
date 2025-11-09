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
            Color.blue.opacity(0.32),
            Color.purple.opacity(0.2),
            Color.black.opacity(0.65)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        ZStack(alignment: .top) {
            backgroundLayer

            ScrollView {
                VStack(spacing: 48) {
                    heroSection
                    searchSection
                    informationSection
                    quickShortcutsSection
                    curatedCollectionsSection
                }
                .padding(.vertical, 72)
                .padding(.horizontal, 32)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.browserBackground)
        .onAppear {
            guard !hasRequestedWeather else { return }
            hasRequestedWeather = true
            weatherProvider.refresh()
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(greeting)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.75))

            Text("Let’s make today extraordinary")
                .font(.system(size: 54, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.white, Color.white.opacity(0.75)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .multilineTextAlignment(.leading)

            Text("Search smarter, jump into your favourite places, and keep an eye on the world at a glance.")
                .font(.title3)
                .foregroundStyle(Color.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassBackground(tint: Color.white.opacity(0.14), cornerRadius: 36)
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Search with \(settings.defaultSearchEngine.displayName)")
                .font(.headline)
                .foregroundStyle(Color.white.opacity(0.85))

            HStack(spacing: 18) {
                Image(systemName: "magnifyingglass")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.65))

                TextField("Search the open web", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Color.white)
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.never)
                    .focused($isSearchFieldFocused)
                    .submitLabel(.search)
                    .onSubmit(submitSearch)

                Button(action: submitSearch) {
                    Label("Go", systemImage: "arrow.up.right.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.plain)
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.browserAccent, Color.white)
                .disabled(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.white.opacity(0.03))
                            .blur(radius: 30)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(isSearchFieldFocused ? 0.4 : 0.16), lineWidth: 1.2)
            )

            if !trendingSearches.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Trending inspirations")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.7))

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], alignment: .leading, spacing: 12) {
                        ForEach(trendingSearches, id: \.self) { suggestion in
                            Button {
                                onSubmitSearch(suggestion)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "sparkles")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(Color.browserAccent)
                                    Text(suggestion)
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(Color.white)
                                        .multilineTextAlignment(.leading)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(0.08))
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassBackground(tint: Color.blue.opacity(0.18), cornerRadius: 36)
    }

    private var informationSection: some View {
        ViewThatFits {
            HStack(alignment: .top, spacing: 28) {
                weatherSection
                focusSection
            }

            VStack(spacing: 28) {
                weatherSection
                focusSection
            }
        }
    }

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Focus Toolkit", systemImage: "circle.bottomhalf.filled")
                .font(.headline)
                .foregroundStyle(Color.white.opacity(0.85))

            Text("Build a calm space for deep work. Set a timer, turn on a playlist, or open your notes in a click.")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.7))

            VStack(alignment: .leading, spacing: 14) {
                focusLinkRow(
                    title: "Start a 25-minute pomodoro",
                    caption: "Timer opens in a new tab",
                    symbol: "timer",
                    destination: URL(string: "https://pomofocus.io")!
                )

                focusLinkRow(
                    title: "Lo-fi beats playlist",
                    caption: "Set the mood while you browse",
                    symbol: "music.note.house",
                    destination: URL(string: "https://music.youtube.com/watch?v=jfKfPfyJRdk")!
                )

                Button {
                    onOpenSettings()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.headline)
                            .foregroundStyle(Color.browserAccent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Personalise browser settings")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.white)
                            Text("Choose your default search, appearance, and more")
                                .font(.caption)
                                .foregroundStyle(Color.white.opacity(0.65))
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(30)
        .liquidGlassBackground(tint: Color.purple.opacity(0.2), cornerRadius: 32)
    }

    private func focusLinkRow(title: String, caption: String, symbol: String, destination: URL) -> some View {
        Button {
            onOpenURL(destination)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(Color.browserAccent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.white)
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.65))
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var weatherSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Today's Weather", systemImage: "cloud.sun.fill")
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
                weatherContent(for: summary)
            } else if let message = weatherProvider.statusMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.68))
            } else if !weatherProvider.isLoading {
                Text("Allow location access to see the weather where you are.")
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.68))
            }
        }
        .padding(30)
        .liquidGlassBackground(tint: Color.cyan.opacity(0.18), cornerRadius: 32)
    }

    private func weatherContent(for summary: HomeWeatherProvider.WeatherSummary) -> some View {
        HStack(spacing: 24) {
            Image(systemName: summary.symbolName)
                .font(.system(size: 54, weight: .medium, design: .rounded))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.browserAccent, Color.white)
                .frame(width: 68, height: 68)

            VStack(alignment: .leading, spacing: 8) {
                Text(summary.temperatureText)
                    .font(.system(size: 48, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)

                Text(summary.conditionText)
                    .font(.title3)
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

    private var quickShortcutsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Quick launchpad")
                .font(.headline)
                .foregroundStyle(Color.white.opacity(0.85))

            Text("Jump right into popular destinations or favourite tasks.")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.65))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 2), spacing: 20) {
                ForEach(quickShortcuts) { shortcut in
                    Button {
                        perform(shortcut.action)
                    } label: {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Image(systemName: shortcut.symbol)
                                    .font(.title2)
                                    .foregroundStyle(Color.browserAccent)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(Color.white.opacity(0.55))
                            }

                            Text(shortcut.title)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Color.white)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(shortcut.subtitle)
                                .font(.footnote)
                                .foregroundStyle(Color.white.opacity(0.7))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(Color.white.opacity(0.07))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var curatedCollectionsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Curated journeys")
                .font(.headline)
                .foregroundStyle(Color.white.opacity(0.85))

            Text("Explore themed collections powered by your default engine.")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.65))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(curatedCollections) { collection in
                        Button {
                            onSubmitSearch(collection.query)
                        } label: {
                            VStack(alignment: .leading, spacing: 16) {
                                Image(systemName: collection.symbol)
                                    .font(.largeTitle)
                                    .foregroundStyle(Color.white.opacity(0.9))
                                    .padding(14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .fill(Color.white.opacity(0.2))
                                    )

                                Text(collection.title)
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(Color.white)

                                Text(collection.description)
                                    .font(.footnote)
                                    .foregroundStyle(Color.white.opacity(0.75))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(28)
                            .frame(width: 280, alignment: .leading)
                            .background(collectionBackground(for: collection))
                            .overlay(
                                RoundedRectangle(cornerRadius: 32, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 0.9)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var trendingSearches: [String] {
        let base = settings.defaultSearchEngine.displayName
        return [
            "Latest in \(base) news",
            "Weekend getaway ideas",
            "Best productivity apps",
            "How to cook seasonal recipes",
            "What's new in tech",
            "Live sports schedule"
        ]
    }

    private var quickShortcuts: [HomeShortcut] {
        [
            .init(
                title: "Open a fresh tab",
                subtitle: "Launch another workspace instantly",
                symbol: "square.2.stack.3d.top.fill",
                action: .newTab
            ),
            .init(
                title: "Catch up on the headlines",
                subtitle: "Top stories curated for you",
                symbol: "newspaper.fill",
                action: .search("today's world news")
            ),
            .init(
                title: "Visit your favourite repos",
                subtitle: "Dive straight into code reviews",
                symbol: "chevron.left.forwardslash.chevron.right",
                action: .open(URL(string: "https://github.com")!)
            ),
            .init(
                title: "Organise your schedule",
                subtitle: "Calendar opens in a focused tab",
                symbol: "calendar",
                action: .open(URL(string: "https://calendar.google.com")!)
            )
        ]
    }

    private var curatedCollections: [CollectionCard] {
        [
            .init(
                title: "Inspiration sparks",
                description: "Beautiful photography, creative prompts, and mindful reads.",
                symbol: "wand.and.stars",
                colors: [Color.purple.opacity(0.6), Color.indigo.opacity(0.5), Color.black.opacity(0.5)],
                query: "creative inspiration articles"
            ),
            .init(
                title: "Build something new",
                description: "Tutorials, tools, and starter kits for your next side project.",
                symbol: "hammer.fill",
                colors: [Color.blue.opacity(0.6), Color.cyan.opacity(0.45), Color.black.opacity(0.4)],
                query: "modern swiftUI tutorial"
            ),
            .init(
                title: "Mindful breaks",
                description: "Short meditations, breathing exercises, and gentle stretches.",
                symbol: "leaf.fill",
                colors: [Color.green.opacity(0.55), Color.teal.opacity(0.45), Color.black.opacity(0.4)],
                query: "guided breathing break"
            )
        ]
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Up late?"
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            Circle()
                .fill(Color.purple.opacity(0.18))
                .frame(width: 420, height: 420)
                .blur(radius: 120)
                .offset(x: -220, y: -260)

            Circle()
                .fill(Color.blue.opacity(0.24))
                .frame(width: 360, height: 360)
                .blur(radius: 110)
                .offset(x: 240, y: -180)

            Circle()
                .fill(Color.cyan.opacity(0.2))
                .frame(width: 480, height: 480)
                .blur(radius: 140)
                .offset(x: 0, y: 320)
        }
    }

    private func collectionBackground(for collection: CollectionCard) -> some View {
        RoundedRectangle(cornerRadius: 32, style: .continuous)
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: collection.colors),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
    }

    private func perform(_ action: HomeShortcut.Action) {
        switch action {
        case .newTab:
            onOpenNewTab()
        case .search(let query):
            onSubmitSearch(query)
        case .open(let url):
            onOpenURL(url)
        }
    }

    private func submitSearch() {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmitSearch(trimmed)
        searchQuery = ""
    }
}

private struct HomeShortcut: Identifiable {
    enum Action {
        case newTab
        case search(String)
        case open(URL)
    }

    let id = UUID()
    let title: String
    let subtitle: String
    let symbol: String
    let action: Action
}

private struct CollectionCard: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let symbol: String
    let colors: [Color]
    let query: String
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
