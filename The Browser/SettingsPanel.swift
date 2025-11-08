import SwiftUI
import Combine

struct SettingsPanel: View {
    @ObservedObject var settings: BrowserSettings
    @Environment(\.dismiss) private var dismiss

    @State private var homePageDraft: String
    @State private var validationMessage: String?
    @State private var customSearchName: String = ""
    @State private var customSearchTemplate: String = ""
    @State private var customSearchError: String?

    init(settings: BrowserSettings) {
        self.settings = settings
        _homePageDraft = State(initialValue: settings.homePage)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header

                    searchEngineCard

                    customSearchCard

                    homePageCard
                }
                .frame(maxWidth: 700, alignment: .leading)
                .padding(24)
            }
            .background(Color.clear)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 480)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Customize The Browser")
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text("Tune the search experience and home screen to match your workflow.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var searchEngineCard: some View {
        SettingsCard(
            title: "Default Search Engine",
            description: "Pick the engine used when you search from the address bar.",
            systemIcon: "magnifyingglass"
        ) {
            Picker("Search Engine", selection: $settings.defaultSearchEngineID) {
                ForEach(settings.availableSearchEngines) { engine in
                    Text(engine.displayName).tag(engine.id)
                }
            }
#if os(iOS)
            .pickerStyle(.menu)
#else
            .frame(maxWidth: 320)
#endif

            if !settings.customSearchEngines.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()

                    Text("Custom Engines")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 12) {
                        ForEach(settings.customSearchEngines) { engine in
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(engine.displayName)
                                        .fontWeight(.medium)
                                    Text(engine.queryTemplate)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button(role: .destructive) {
                                    settings.removeCustomSearchEngine(id: engine.id)
                                    customSearchError = nil
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                        .labelStyle(.iconOnly)
                                }
                                .buttonStyle(.borderless)
                                .help("Remove this custom search engine")
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.thinMaterial)
                            )
                        }
                    }
                }
            }
        }
    }

    private var customSearchCard: some View {
        SettingsCard(
            title: "Add Custom Search Engine",
            description: "Use {query} as a placeholder for what you type in the address bar.",
            systemIcon: "slider.horizontal.3"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Display name", text: $customSearchName)
                        .textFieldStyleSettings()

                    TextField("Search URL (use {query})", text: $customSearchTemplate)
                        .textFieldStyleSettings()
                }

                if let customSearchError {
                    Text(customSearchError)
                        .font(.footnote)
                        .foregroundColor(.red)
                }

                HStack(spacing: 12) {
                    Button("Add Search Engine", action: addCustomSearchEngine)
                        .buttonStyle(.borderedProminent)

                    if !customSearchName.isEmpty || !customSearchTemplate.isEmpty {
                        Button("Clear") {
                            customSearchName = ""
                            customSearchTemplate = ""
                            customSearchError = nil
                        }
                    }
                }
            }
        }
    }

    private var homePageCard: some View {
        SettingsCard(
            title: "Home Page",
            description: "Choose where new tabs start, or fall back to the built-in home view.",
            systemIcon: "house.fill"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Home page URL", text: $homePageDraft)
                    .textFieldStyleSettings()
                    .onSubmit(saveHomePage)

                if let validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundColor(.red)
                }

                HStack(spacing: 12) {
                    Button("Save Home Page", action: saveHomePage)
                        .buttonStyle(.borderedProminent)

                    Button("Use Built-In Home View") {
                        settings.useDefaultHomeContent()
                        homePageDraft = ""
                        validationMessage = nil
                    }
                }

                if let url = settings.homePageURL {
                    Label(url.absoluteString, systemImage: "link")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Currently showing the built-in home view.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let description: String
    let systemIcon: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.browserAccent.opacity(0.18))
                        .frame(width: 44, height: 44)

                    Image(systemName: systemIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color.browserAccent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            content()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThickMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private extension View {
    func textFieldStyleSettings() -> some View {
#if os(macOS)
        self.textFieldStyle(.roundedBorder)
#else
        self
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .keyboardType(.URL)
            .textFieldStyle(.roundedBorder)
#endif
    }
}
