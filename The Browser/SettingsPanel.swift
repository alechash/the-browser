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
            Form {
                Section("Default Search Engine") {
                    Picker("Search Engine", selection: $settings.defaultSearchEngineID) {
                        ForEach(settings.availableSearchEngines) { engine in
                            Text(engine.displayName).tag(engine.id)
                        }
                    }
#if os(iOS)
                    .pickerStyle(.menu)
#endif

                    if !settings.customSearchEngines.isEmpty {
                        ForEach(settings.customSearchEngines) { engine in
                            HStack {
                                Text(engine.displayName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button(role: .destructive) {
                                    settings.removeCustomSearchEngine(id: engine.id)
                                    customSearchError = nil
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }

                Section("Add Custom Search Engine") {
                    TextField("Display name", text: $customSearchName)
                    TextField("Search URL (use {query})", text: $customSearchTemplate)
#if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .disableAutocorrection(true)
#endif

                    if let customSearchError {
                        Text(customSearchError)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }

                    Button("Add Search Engine", action: addCustomSearchEngine)
                        .buttonStyle(.borderedProminent)
                }

                Section("Home Page") {
                    TextField("Home page URL", text: $homePageDraft)
#if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .disableAutocorrection(true)
#endif
                        .onSubmit(saveHomePage)

                    if let validationMessage {
                        Text(validationMessage)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }

                    Button("Save Home Page", action: saveHomePage)
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)

                    Button("Use Built-In Home View") {
                        settings.useDefaultHomeContent()
                        homePageDraft = ""
                        validationMessage = nil
                    }
                    .padding(.top, 2)
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
}
