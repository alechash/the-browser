import SwiftUI
import Combine

final class BrowserSettings: ObservableObject {
    struct SearchEngine: Identifiable, Equatable, Codable {
        let id: String
        let displayName: String
        let queryTemplate: String
        let isBuiltIn: Bool

        init(id: String, displayName: String, queryTemplate: String, isBuiltIn: Bool = false) {
            self.id = id
            self.displayName = displayName
            self.queryTemplate = queryTemplate
            self.isBuiltIn = isBuiltIn
        }

        func searchURL(for query: String) -> URL {
            let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query

            if queryTemplate.contains("{query}") {
                let replaced = queryTemplate.replacingOccurrences(of: "{query}", with: encodedQuery)
                if let url = URL(string: replaced) {
                    return url
                }
            } else if var components = URLComponents(string: queryTemplate) {
                var items = components.queryItems ?? []
                items.append(URLQueryItem(name: "q", value: query))
                components.queryItems = items
                if let url = components.url {
                    return url
                }
            }

            let fallbackBase = "https://www.google.com/search"
            var fallbackComponents = URLComponents(string: fallbackBase)!
            fallbackComponents.queryItems = [URLQueryItem(name: "q", value: query)]
            return fallbackComponents.url ?? URL(string: fallbackBase)!
        }

        static var builtIn: [SearchEngine] {
            [
                SearchEngine(id: "google", displayName: "Google", queryTemplate: "https://www.google.com/search?q={query}", isBuiltIn: true),
                SearchEngine(id: "duckduckgo", displayName: "DuckDuckGo", queryTemplate: "https://duckduckgo.com/?q={query}", isBuiltIn: true),
                SearchEngine(id: "bing", displayName: "Bing", queryTemplate: "https://www.bing.com/search?q={query}", isBuiltIn: true),
                SearchEngine(id: "chatgpt", displayName: "ChatGPT", queryTemplate: "https://chat.openai.com/?q={query}", isBuiltIn: true),
                SearchEngine(id: "claude", displayName: "Claude", queryTemplate: "https://claude.ai/new?q={query}", isBuiltIn: true),
                SearchEngine(id: "gemini", displayName: "Gemini", queryTemplate: "https://gemini.google.com/app?query={query}", isBuiltIn: true)
            ]
        }

        static var defaultID: String { builtIn.first?.id ?? "google" }
    }

    @Published private(set) var availableSearchEngines: [SearchEngine]
    @Published private(set) var customSearchEngines: [SearchEngine] {
        didSet {
            persistCustomSearchEngines()
            refreshAvailableSearchEngines()
        }
    }

    @Published var defaultSearchEngineID: String {
        didSet {
            userDefaults.set(defaultSearchEngineID, forKey: Keys.searchEngine)
        }
    }

    @Published var homePage: String {
        didSet {
            userDefaults.set(homePage, forKey: Keys.homePage)
        }
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        // Stage custom search engines without using self
        let loadedCustomEngines: [SearchEngine]
        if let data = userDefaults.data(forKey: Keys.customSearchEngines),
           let decoded = try? JSONDecoder().decode([SearchEngine].self, from: data) {
            loadedCustomEngines = decoded
        } else {
            loadedCustomEngines = []
        }

        // Stage available engines
        let stagedAvailable = SearchEngine.builtIn + loadedCustomEngines

        // Stage default search engine id
        let stagedDefaultID: String
        if let storedID = userDefaults.string(forKey: Keys.searchEngine),
           stagedAvailable.contains(where: { $0.id == storedID }) {
            stagedDefaultID = storedID
        } else {
            stagedDefaultID = SearchEngine.defaultID
            userDefaults.set(stagedDefaultID, forKey: Keys.searchEngine)
        }

        // Stage home page
        let stagedHome: String
        if let storedHome = userDefaults.string(forKey: Keys.homePage) {
            stagedHome = storedHome
        } else {
            stagedHome = ""
        }

        // Now assign to stored properties in a safe order
        self.customSearchEngines = loadedCustomEngines
        self.availableSearchEngines = stagedAvailable
        self.defaultSearchEngineID = stagedDefaultID
        self.homePage = stagedHome

        // Ensure consistency in case of later mutations
        refreshAvailableSearchEngines()
    }

    func applyHomePageInput(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if BrowserViewModel.url(from: trimmed) != nil {
            homePage = trimmed
            return true
        }

        if let components = URLComponents(string: "https://\(trimmed)"),
           let host = components.host, !host.isEmpty {
            homePage = components.string ?? trimmed
            return true
        }

        return false
    }

    func useDefaultHomeContent() {
        homePage = ""
    }

    func searchURL(for query: String) -> URL {
        defaultSearchEngine.searchURL(for: query)
    }

    var defaultSearchEngine: SearchEngine {
        availableSearchEngines.first(where: { $0.id == defaultSearchEngineID }) ?? SearchEngine.builtIn.first!
    }

    var homePageURL: URL? {
        guard !homePage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if let url = BrowserViewModel.url(from: homePage) {
            return url
        }
        return nil
    }

    @discardableResult
    func addCustomSearchEngine(name: String, template: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTemplate = template.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty, !trimmedTemplate.isEmpty else { return false }
        let hasPlaceholder = trimmedTemplate.contains("{query}")
        let validationString: String
        if hasPlaceholder {
            validationString = trimmedTemplate.replacingOccurrences(of: "{query}", with: "test")
        } else if trimmedTemplate.contains("?") {
            validationString = "\(trimmedTemplate)&q=test"
        } else {
            validationString = "\(trimmedTemplate)?q=test"
        }

        guard URL(string: validationString) != nil else { return false }

        let identifier = "custom-\(UUID().uuidString)"
        let engine = SearchEngine(id: identifier, displayName: trimmedName, queryTemplate: trimmedTemplate, isBuiltIn: false)
        customSearchEngines.append(engine)
        defaultSearchEngineID = engine.id
        return true
    }

    func removeCustomSearchEngine(id: String) {
        guard let index = customSearchEngines.firstIndex(where: { $0.id == id }) else { return }
        customSearchEngines.remove(at: index)
        if !availableSearchEngines.contains(where: { $0.id == defaultSearchEngineID }) {
            defaultSearchEngineID = SearchEngine.defaultID
        }
    }

    private func persistCustomSearchEngines() {
        if let data = try? JSONEncoder().encode(customSearchEngines) {
            userDefaults.set(data, forKey: Keys.customSearchEngines)
        } else {
            userDefaults.removeObject(forKey: Keys.customSearchEngines)
        }
    }

    private func refreshAvailableSearchEngines() {
        availableSearchEngines = SearchEngine.builtIn + customSearchEngines
        if !availableSearchEngines.contains(where: { $0.id == defaultSearchEngineID }) {
            defaultSearchEngineID = SearchEngine.defaultID
        }
    }

    private enum Keys {
        static let searchEngine = "BrowserSearchEngine"
        static let homePage = "BrowserHomePage"
        static let customSearchEngines = "BrowserCustomSearchEngines"
    }
}
