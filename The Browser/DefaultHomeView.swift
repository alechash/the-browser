import SwiftUI

struct DefaultHomeView: View {
    @ObservedObject var settings: BrowserSettings
    let onSubmitSearch: (String) -> Void

    @State private var searchQuery = ""
    @FocusState private var isSearchFieldFocused: Bool
    @StateObject private var weatherProvider = HomeWeatherProvider()
    @State private var hasRequestedWeather = false

    var body: some View {
        ScrollView {
            VStack(spacing: 40) {
                headerSection
                searchSection
                weatherSection
            }
            .padding(.vertical, 64)
            .padding(.horizontal, 32)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.browserBackground)
        .onAppear {
            guard !hasRequestedWeather else { return }
            hasRequestedWeather = true
            weatherProvider.refresh()
        }
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            Text("Welcome back")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(Color.browserAccent)

            Text("Search the web or jump into your next destination.")
                .font(.title3)
                .foregroundStyle(Color.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Search with \(settings.defaultSearchEngine.displayName)")
                .font(.headline)
                .foregroundStyle(Color.white.opacity(0.9))

            HStack(spacing: 16) {
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(Color.white.opacity(0.7))

                TextField("Search the web", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Color.white)
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.never)
                    .focused($isSearchFieldFocused)
                    .onSubmit(submitSearch)

                Button(action: submitSearch) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.browserAccent, Color.white)
                .disabled(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(isSearchFieldFocused ? 0.25 : 0.12), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var weatherSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Today's Weather", systemImage: "cloud.sun.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.headline)
                    .foregroundStyle(Color.white.opacity(0.9))

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
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.7))
            } else if !weatherProvider.isLoading {
                Text("Allow location access to see the weather where you are.")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func weatherContent(for summary: HomeWeatherProvider.WeatherSummary) -> some View {
        HStack(spacing: 24) {
            Image(systemName: summary.symbolName)
                .font(.system(size: 48))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.browserAccent, Color.white)

            VStack(alignment: .leading, spacing: 6) {
                Text(summary.temperatureText)
                    .font(.system(size: 48, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)

                Text(summary.conditionText)
                    .font(.title3)
                    .foregroundStyle(Color.white.opacity(0.8))

                if let location = summary.locationName {
                    Text(location)
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.7))
                }
            }

            Spacer()
        }
    }

    private func submitSearch() {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmitSearch(trimmed)
        searchQuery = ""
    }
}

#Preview {
    DefaultHomeView(
        settings: BrowserSettings(),
        onSubmitSearch: { _ in }
    )
    .background(Color.browserBackground)
}
