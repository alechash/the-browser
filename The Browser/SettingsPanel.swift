import SwiftUI
import Combine

struct SettingsPanel: View {
    @ObservedObject var settings: BrowserSettings
    @Environment(\.dismiss) private var dismiss

    @State private var homePageDraft: String
    @State private var homePageValidationMessage: String?
    @State private var newSearchEngineName: String = ""
    @State private var newSearchEngineTemplate: String = ""
    @State private var searchEngineValidationMessage: String?

    init(settings: BrowserSettings) {
        self.settings = settings
        _homePageDraft = State(initialValue: settings.homePage)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Default Search Engine") {
                    Picker("Search Engine", selection: $settings.defaultSearchEngineID) {
                        ForEach(settings.availableSearchEngines) { engine in
                            Text(engine.name).tag(engine.id)
                        }
                    }
#if os(iOS)
                    .pickerStyle(.segmented)
#endif
                }

                if !settings.customSearchEngines.isEmpty {
                    Section("Custom Engines") {
                        ForEach(settings.customSearchEngines) { engine in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(engine.name)
                                    Text(engine.urlTemplate)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    settings.removeCustomSearchEngine(engine)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }

                Section("Add Custom Search Engine") {
                    Text("Use {query} as a placeholder where the search term should appear.")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    TextField("Display name", text: $newSearchEngineName)

                    TextField("Search URL template", text: $newSearchEngineTemplate)
#if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .disableAutocorrection(true)
#endif

                    if let message = searchEngineValidationMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }

                    Button("Add Search Engine", action: addSearchEngine)
                        .buttonStyle(.borderedProminent)
                }

                Section("Home Page") {
                    Picker("Start Page", selection: $settings.homePageMode) {
                        ForEach(BrowserSettings.HomePageMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
#if os(iOS)
                    .pickerStyle(.segmented)
#endif

                    if settings.homePageMode == .custom {
                        TextField("Home page URL", text: $homePageDraft)
#if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .disableAutocorrection(true)
#endif
                        .onSubmit(saveHomePage)

                        if let message = homePageValidationMessage {
                            Text(message)
                                .font(.footnote)
                                .foregroundColor(.red)
                        }

                        Button("Save Home Page", action: saveHomePage)
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 4)
                    } else {
                        Text("New tabs open with a friendly SwiftUI hello screen. Set a custom URL if you'd prefer a website instead.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(minWidth: 360, minHeight: 260)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onChange(of: settings.homePageMode) { mode in
            if mode == .custom {
                homePageDraft = settings.homePage
            } else {
                homePageValidationMessage = nil
            }
        }
    }

    private func saveHomePage() {
        if settings.applyHomePageInput(homePageDraft) {
            homePageValidationMessage = nil
            homePageDraft = settings.homePage
        } else {
            homePageValidationMessage = "Enter a valid URL or host name."
        }
    }

    private func addSearchEngine() {
        if settings.addCustomSearchEngine(name: newSearchEngineName, template: newSearchEngineTemplate) {
            newSearchEngineName = ""
            newSearchEngineTemplate = ""
            searchEngineValidationMessage = nil
        } else {
            searchEngineValidationMessage = "Provide a name and URL template containing {query}."
        }
    }
}
