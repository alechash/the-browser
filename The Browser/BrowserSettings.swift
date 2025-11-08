import SwiftUI
import Combine

final class BrowserSettings: ObservableObject {
    struct SearchEngine: Identifiable, Codable, Equatable {
        let id: String
        var name: String
        var urlTemplate: String
        var isCustom: Bool

        func searchURL(for query: String) -> URL {
            let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            let replaced = urlTemplate.replacingOccurrences(of: "{query}", with: encodedQuery)
            if let url = URL(string: replaced) {
                return url
            }
            // Fallback to Google if the template is invalid at runtime
            return URL(string: "https://www.google.com/search?q=\(encodedQuery)")!
        }
    }

    enum HomePageMode: String, CaseIterable, Identifiable {
        case welcome
        case custom

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .welcome:
                return "Hello start page"
            case .custom:
                return "Custom website"
            }
        }
    }

    @Published var defaultSearchEngineID: String {
        didSet {
            userDefaults.set(defaultSearchEngineID, forKey: Keys.searchEngineID)
        }
    }

    @Published var customSearchEngines: [SearchEngine] {
        didSet {
            persistCustomSearchEngines()
            ensureValidDefaultSearchEngine()
        }
    }

    @Published var homePageMode: HomePageMode {
        didSet {
            userDefaults.set(homePageMode.rawValue, forKey: Keys.homePageMode)
        }
    }

    @Published var homePage: String {
        didSet {
            userDefaults.set(homePage, forKey: Keys.homePage)
        }
    }

    private let userDefaults: UserDefaults

    private static let builtInSearchEngines: [SearchEngine] = [
        SearchEngine(id: "google", name: "Google", urlTemplate: "https://www.google.com/search?q={query}", isCustom: false),
        SearchEngine(id: "duckDuckGo", name: "DuckDuckGo", urlTemplate: "https://duckduckgo.com/?q={query}", isCustom: false),
        SearchEngine(id: "bing", name: "Bing", urlTemplate: "https://www.bing.com/search?q={query}", isCustom: false),
        SearchEngine(id: "perplexity", name: "Perplexity", urlTemplate: "https://www.perplexity.ai/search?q={query}", isCustom: false),
        SearchEngine(id: "you", name: "You.com", urlTemplate: "https://you.com/search?q={query}", isCustom: false),
        SearchEngine(id: "phind", name: "Phind", urlTemplate: "https://www.phind.com/search?q={query}", isCustom: false)
    ]

    private static let defaultSearchEngineID = builtInSearchEngines.first?.id ?? "google"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        if let storedID = userDefaults.string(forKey: Keys.searchEngineID) {
            defaultSearchEngineID = storedID
        } else {
            defaultSearchEngineID = Self.defaultSearchEngineID
        }

        if let data = userDefaults.data(forKey: Keys.customSearchEngines),
           let decoded = try? JSONDecoder().decode([SearchEngine].self, from: data) {
            customSearchEngines = decoded
        } else {
            customSearchEngines = []
        }

        if let storedMode = userDefaults.string(forKey: Keys.homePageMode),
           let mode = HomePageMode(rawValue: storedMode) {
            homePageMode = mode
        } else if let storedHome = userDefaults.string(forKey: Keys.homePage), !storedHome.isEmpty {
            homePageMode = .custom
        } else {
            homePageMode = .welcome
        }

        homePage = userDefaults.string(forKey: Keys.homePage) ?? ""

        ensureValidDefaultSearchEngine()
    }

    var availableSearchEngines: [SearchEngine] {
        Self.builtInSearchEngines + customSearchEngines
    }

    var defaultSearchEngine: SearchEngine {
        availableSearchEngines.first(where: { $0.id == defaultSearchEngineID }) ?? Self.builtInSearchEngines[0]
    }

    func searchURL(for query: String) -> URL {
        defaultSearchEngine.searchURL(for: query)
    }

    func addCustomSearchEngine(name: String, template: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTemplate = template.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty,
              trimmedTemplate.contains("{query}"),
              URL(string: trimmedTemplate.replacingOccurrences(of: "{query}", with: "test")) != nil else {
            return false
        }

        let newEngine = SearchEngine(
            id: UUID().uuidString,
            name: trimmedName,
            urlTemplate: trimmedTemplate,
            isCustom: true
        )

        customSearchEngines.append(newEngine)
        defaultSearchEngineID = newEngine.id
        return true
    }

    func removeCustomSearchEngine(_ engine: SearchEngine) {
        if let index = customSearchEngines.firstIndex(of: engine) {
            customSearchEngines.remove(at: index)
        }
    }

    func removeCustomSearchEngines(at offsets: IndexSet) {
        customSearchEngines.remove(atOffsets: offsets)
    }

    func applyHomePageInput(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if BrowserViewModel.url(from: trimmed) != nil {
            homePage = trimmed
            homePageMode = .custom
            return true
        }

        if let components = URLComponents(string: "https://\(trimmed)"),
           let host = components.host, !host.isEmpty {
            homePage = components.string ?? trimmed
            homePageMode = .custom
            return true
        }

        return false
    }

    func useWelcomeHomePage() {
        homePageMode = .welcome
    }

    var homePageURL: URL? {
        guard homePageMode == .custom else { return nil }
        if let url = BrowserViewModel.url(from: homePage) {
            return url
        }
        if let url = URL(string: homePage), url.scheme != nil {
            return url
        }
        return nil
    }

    private func persistCustomSearchEngines() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(customSearchEngines) {
            userDefaults.set(data, forKey: Keys.customSearchEngines)
        }
    }

    private func ensureValidDefaultSearchEngine() {
        if availableSearchEngines.contains(where: { $0.id == defaultSearchEngineID }) {
            return
        }
        defaultSearchEngineID = Self.defaultSearchEngineID
    }

    private enum Keys {
        static let searchEngineID = "BrowserSearchEngine"
        static let customSearchEngines = "BrowserCustomSearchEngines"
        static let homePage = "BrowserHomePage"
        static let homePageMode = "BrowserHomePageMode"
    }
}
