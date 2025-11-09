import SwiftUI

struct HistoryView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @State private var searchQuery = ""
    @FocusState private var isSearchFieldFocused: Bool

    private let backgroundGradient = LinearGradient(
        gradient: Gradient(colors: [
            Color.purple.opacity(0.32),
            Color.blue.opacity(0.24),
            Color.black.opacity(0.65)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredHistory: [BrowserViewModel.HistoryEntry] {
        let query = trimmedQuery.lowercased()
        guard !query.isEmpty else { return viewModel.history }

        return viewModel.history.filter { entry in
            entry.displayTitle.lowercased().contains(query) ||
            entry.displayURL.lowercased().contains(query)
        }
    }

    private var groupedHistory: [HistorySection] {
        let calendar = Calendar.current
        let sections = Dictionary(grouping: filteredHistory) { entry in
            calendar.startOfDay(for: entry.lastVisited)
        }
        .map { day, entries in
            HistorySection(
                date: day,
                title: sectionTitle(for: day),
                entries: entries.sorted { $0.lastVisited > $1.lastVisited }
            )
        }
        .sorted { lhs, rhs in
            lhs.date > rhs.date
        }

        return sections
    }

    private var hasHistory: Bool {
        !viewModel.history.isEmpty
    }

    var body: some View {
        ZStack(alignment: .top) {
            backgroundLayer

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 32) {
                    header

                    if groupedHistory.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 28) {
                            ForEach(groupedHistory) { section in
                                sectionView(for: section)
                            }
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 48)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Browsing history")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)

                Text("Revisit the pages you've opened recently.")
                    .font(.callout)
                    .foregroundStyle(Color.white.opacity(0.7))
            }

            searchField
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.7))

            TextField("Search history", text: $searchQuery)
                .textFieldStyle(.plain)
                .foregroundStyle(Color.white)
                .focused($isSearchFieldFocused)
#if os(iOS)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.search)
#endif

            if !trimmedQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .liquidGlassBackground(tint: Color.white.opacity(0.12), cornerRadius: 22, includeShadow: false)
    }

    private func sectionView(for section: HistorySection) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(section.title)
                .font(.headline)
                .foregroundStyle(Color.white.opacity(0.78))

            VStack(spacing: 12) {
                ForEach(section.entries) { entry in
                    HistoryRow(
                        entry: entry,
                        timestamp: timestamp(for: entry),
                        openAction: { viewModel.openHistoryEntry(entry) },
                        openInNewTabAction: { viewModel.openHistoryEntry(entry, inNewTab: true) }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: hasHistory ? "magnifyingglass" : "clock")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Color.browserAccent)

            Text(hasHistory ? "No results" : "Nothing here yet")
                .font(.headline)
                .foregroundStyle(Color.white.opacity(0.85))

            Text(hasHistory ? "Try a different search term." : "Visit a site to start building your history.")
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .liquidGlassBackground(tint: Color.white.opacity(0.1), cornerRadius: 28)
    }

    private func timestamp(for entry: BrowserViewModel.HistoryEntry) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(entry.lastVisited) {
            return Self.timeFormatter.string(from: entry.lastVisited)
        }
        return Self.dateFormatter.string(from: entry.lastVisited)
    }

    private func sectionTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        return Self.sectionDateFormatter.string(from: date)
    }

    private var backgroundLayer: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            Circle()
                .fill(Color.purple.opacity(0.18))
                .frame(width: 360, height: 360)
                .blur(radius: 120)
                .offset(x: -240, y: -200)

            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 320, height: 320)
                .blur(radius: 110)
                .offset(x: 260, y: -160)

            Circle()
                .fill(Color.cyan.opacity(0.18))
                .frame(width: 420, height: 420)
                .blur(radius: 150)
                .offset(x: -40, y: 320)
        }
    }

    private struct HistorySection: Identifiable {
        let date: Date
        let title: String
        let entries: [BrowserViewModel.HistoryEntry]

        var id: Date { date }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let sectionDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct HistoryRow: View {
    let entry: BrowserViewModel.HistoryEntry
    let timestamp: String
    let openAction: () -> Void
    let openInNewTabAction: () -> Void

    @State private var isHovering = false

    private var hostText: String {
        entry.url.host ?? entry.url.absoluteString
    }

    var body: some View {
        Button(action: openAction) {
            HStack(alignment: .center, spacing: 16) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.browserAccent.opacity(0.22))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Image(systemName: "globe")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.browserAccent)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(2)

                    Text(entry.displayURL)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.68))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(timestamp)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.7))

                    Text(hostText)
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 20)
            .liquidGlassBackground(
                tint: Color.white.opacity(isHovering ? 0.18 : 0.12),
                cornerRadius: 22,
                includeShadow: false
            )
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
#if os(macOS)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
#endif
        .contextMenu {
            Button(action: openInNewTabAction) {
                Label("Open in New Tab", systemImage: "plus.square.on.square")
            }
        }
    }
}

#Preview {
    HistoryView(viewModel: BrowserViewModel(settings: BrowserSettings()))
}
