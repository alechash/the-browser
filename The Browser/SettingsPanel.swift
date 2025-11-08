import SwiftUI
import Combine

struct SettingsPanel: View {
    @ObservedObject var settings: BrowserSettings
    @Environment(\.dismiss) private var dismiss

    @State private var homePageDraft: String
    @State private var validationMessage: String?

    init(settings: BrowserSettings) {
        self.settings = settings
        _homePageDraft = State(initialValue: settings.homePage)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Default Search Engine") {
                    Picker("Search Engine", selection: $settings.defaultSearchEngine) {
                        ForEach(BrowserSettings.SearchEngine.allCases) { engine in
                            Text(engine.displayName).tag(engine)
                        }
                    }
#if os(iOS)
                    .pickerStyle(.segmented)
#endif
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
}
