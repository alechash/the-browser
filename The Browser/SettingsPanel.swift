import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct SettingsPanel: View {
    @ObservedObject var settings: BrowserSettings
    @Environment(\.dismiss) private var dismiss

    @State private var homePageDraft: String
    @State private var validationMessage: String?
    @State private var customSearchName: String = ""
    @State private var customSearchTemplate: String = ""
    @State private var customSearchError: String?
    @State private var selectedSection: Section = .general

    init(settings: BrowserSettings) {
        self.settings = settings
        _homePageDraft = State(initialValue: settings.homePage)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    header
                    sectionPicker
                    sectionDescription
                    content(for: selectedSection)
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(panelBackground.ignoresSafeArea())
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(minWidth: 540, minHeight: 520)
        .onChange(of: homePageDraft) { _ in validationMessage = nil }
        .onChange(of: customSearchName) { _ in customSearchError = nil }
        .onChange(of: customSearchTemplate) { _ in customSearchError = nil }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Customize The Browser")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Tailor search, startup behavior, and the tools you rely on every day.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sectionPicker: some View {
        Picker("Section", selection: $selectedSection) {
            ForEach(Section.allCases) { section in
                Text(section.title).tag(section)
            }
        }
        .pickerStyle(.segmented)
    }

    private var sectionDescription: some View {
        Text(selectedSection.tagline)
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func content(for section: Section) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            switch section {
            case .general:
                homePageCard
            case .search:
                defaultSearchCard
                customSearchCard
            }
        }
    }

    private var homePageCard: some View {
        SettingsCard(
            title: "Startup Home Page",
            subtitle: "Decide what appears when The Browser launches or opens a new tab.",
            icon: "house.fill"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom Home URL")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("https://example.com", text: $homePageDraft)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(inputFieldBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .onSubmit(saveHomePage)
#if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .disableAutocorrection(true)
#endif
                }

                if let validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Text(homeStatusDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button("Save Changes", action: saveHomePage)
                        .buttonStyle(.borderedProminent)

                    Button("Use Built-In Home View") {
                        settings.useDefaultHomeContent()
                        homePageDraft = ""
                        validationMessage = nil
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var defaultSearchCard: some View {
        SettingsCard(
            title: "Default Search",
            subtitle: "Choose the engine that powers address bar searches.",
            icon: "magnifyingglass"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Search Engine")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Menu {
                        Picker("Search Engine", selection: $settings.defaultSearchEngineID) {
                            ForEach(settings.availableSearchEngines) { engine in
                                Text(engine.displayName).tag(engine.id)
                            }
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(currentDefaultEngineName)
                                    .font(.headline)
                                Text("Tap to switch search providers")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(inputFieldBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }

                if !settings.customSearchEngines.isEmpty {
                    Text("Custom engines will also appear in this list, making it easy to switch between your favorite tools.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("You can add additional engines below — they'll be available here immediately.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var customSearchCard: some View {
        SettingsCard(
            title: "Custom Search Engines",
            subtitle: "Create shortcuts for the services you search most.",
            icon: "slider.horizontal.3"
        ) {
            VStack(alignment: .leading, spacing: 20) {
                if settings.customSearchEngines.isEmpty {
                    Text("Add a search engine with a \"{query}\" placeholder to start building your personalized list.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(settings.customSearchEngines) { engine in
                            HStack(alignment: .firstTextBaseline, spacing: 16) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(engine.displayName)
                                        .font(.headline)
                                    Text(engine.queryTemplate)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }

                                Spacer()

                                if engine.id == settings.defaultSearchEngineID {
                                    Label("Default", systemImage: "star.fill")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .foregroundStyle(Color.accentColor)
                                        .background(Color.accentColor.opacity(0.12))
                                        .clipShape(Capsule())
                                }

                                Button {
                                    settings.removeCustomSearchEngine(id: engine.id)
                                    customSearchError = nil
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                        .labelStyle(.iconOnly)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.red)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(inputFieldBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Add a new engine")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("Display name", text: $customSearchName)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(inputFieldBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    TextField("Search URL (use {query})", text: $customSearchTemplate)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(inputFieldBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .onSubmit(addCustomSearchEngine)
#if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .disableAutocorrection(true)
#endif

                    if let customSearchError {
                        Text(customSearchError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button("Add Search Engine", action: addCustomSearchEngine)
                        .buttonStyle(.borderedProminent)
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

    private func addCustomSearchEngine() {
        if settings.addCustomSearchEngine(name: customSearchName, template: customSearchTemplate) {
            customSearchError = nil
            customSearchName = ""
            customSearchTemplate = ""
        } else {
            customSearchError = "Enter a valid name and URL template."
        }
    }

    private var homeStatusDescription: String {
        let trimmed = settings.homePage.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Currently showing the built-in home experience."
        } else {
            return "Currently opens \(trimmed)."
        }
    }

    private var currentDefaultEngineName: String {
        settings.availableSearchEngines
            .first(where: { $0.id == settings.defaultSearchEngineID })?
            .displayName ?? "Search Engine"
    }

    private var inputFieldBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.primary.opacity(0.05))
    }

    private var panelBackground: Color {
#if os(macOS)
        Color(nsColor: .underPageBackgroundColor)
#else
        Color(uiColor: .systemGroupedBackground)
#endif
    }

    private enum Section: String, CaseIterable, Identifiable {
        case general
        case search

        var id: Self { self }

        var title: String {
            switch self {
            case .general: return "General"
            case .search: return "Search"
            }
        }

        var tagline: String {
            switch self {
            case .general:
                return "Control the home experience and startup destination."
            case .search:
                return "Fine-tune how and where your queries are sent."
            }
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.accentColor.opacity(0.18))
                        .frame(width: 48, height: 48)

                    Image(systemName: icon)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}
