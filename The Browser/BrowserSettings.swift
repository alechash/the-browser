import SwiftUI
import Combine

final class BrowserSettings: ObservableObject {
    enum SearchEngine: String, CaseIterable, Identifiable {
        case google
        case duckDuckGo
        case bing

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .google:
                return "Google"
            case .duckDuckGo:
                return "DuckDuckGo"
            case .bing:
                return "Bing"
            }
        }

        fileprivate func searchURL(for query: String) -> URL {
            let base: String
            switch self {
            case .google:
                base = "https://www.google.com/search"
            case .duckDuckGo:
                base = "https://duckduckgo.com/"
            case .bing:
                base = "https://www.bing.com/search"
            }

            var components = URLComponents(string: base)!
            components.queryItems = [URLQueryItem(name: "q", value: query)]
            return components.url ?? URL(string: base)!
        }
    }

    @Published var defaultSearchEngine: SearchEngine {
        didSet {
            userDefaults.set(defaultSearchEngine.rawValue, forKey: Keys.searchEngine)
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

        if let rawValue = userDefaults.string(forKey: Keys.searchEngine),
           let storedEngine = SearchEngine(rawValue: rawValue) {
            defaultSearchEngine = storedEngine
        } else {
            defaultSearchEngine = .google
        }

        if let storedHome = userDefaults.string(forKey: Keys.homePage), !storedHome.isEmpty {
            homePage = storedHome
        } else {
            homePage = "https://www.apple.com"
        }
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

    func searchURL(for query: String) -> URL {
        defaultSearchEngine.searchURL(for: query)
    }

    var homePageURL: URL {
        if let url = BrowserViewModel.url(from: homePage) {
            return url
        }
        return URL(string: "https://www.apple.com")!
    }

    private enum Keys {
        static let searchEngine = "BrowserSearchEngine"
        static let homePage = "BrowserHomePage"
    }
}
