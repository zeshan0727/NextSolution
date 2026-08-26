import Foundation

struct ArticleManifest: Decodable {
    let entries: [PublishedArticle]
}

struct ArticleCategory: Decodable {
    let id: String?
    let label: String?
}

struct PublishedArticle: Decodable, Identifiable, Hashable {
    let name: String
    let title: String
    let description: String
    let href: String
    let version: String?
    let category: ArticleCategory?

    var id: String { cleanURL.absoluteString }

    /// The exact URL published by the website manifest/feed.
    ///
    /// Some newly published articles are available immediately at their
    /// legacy `.html` route before a clean `/slug/` copy exists. Social
    /// crawlers such as X must receive the URL that definitely serves the
    /// article metadata, otherwise the link card can fail with a 404/no card.
    var publishedURL: URL {
        if let absolute = URL(string: href), absolute.scheme != nil {
            return absolute
        }

        let trimmed = href.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "https://nextjailbreak.com/\(trimmed)")!
    }

    /// Clean canonical-style URL retained for deduplication/history.
    var cleanURL: URL {
        Self.cleaned(url: publishedURL)
    }

    /// Dedicated sharing URL for X/Twitter cards.
    ///
    /// Use the exact published route as the crawl target, then add a small
    /// query string so X can refresh a previously cached card. This avoids
    /// forcing a `/slug/` route that may not exist yet for brand-new articles.
    var socialShareURL: URL {
        guard var components = URLComponents(url: publishedURL, resolvingAgainstBaseURL: false) else {
            return publishedURL
        }

        var items = components.queryItems ?? []
        items.removeAll { ["utm_source", "utm_medium", "utm_campaign", "v"].contains($0.name) }
        items.append(URLQueryItem(name: "utm_source", value: "nextpost"))
        items.append(URLQueryItem(name: "utm_medium", value: "x"))
        items.append(URLQueryItem(name: "utm_campaign", value: "article_share"))
        if let version, !version.isEmpty {
            items.append(URLQueryItem(name: "v", value: version))
        }
        components.queryItems = items
        return components.url ?? publishedURL
    }

    private static func cleaned(url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        components.query = nil
        components.fragment = nil

        var path = components.path
        if path.hasSuffix(".html") {
            path = String(path.dropLast(5)) + "/"
        } else if !path.hasSuffix("/") {
            path += "/"
        }
        components.path = path
        return components.url ?? url
    }

    static func == (lhs: PublishedArticle, rhs: PublishedArticle) -> Bool {
        lhs.cleanURL == rhs.cleanURL
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(cleanURL.absoluteString)
    }
}

extension ArticleCategory {
    static let empty = ArticleCategory(id: nil, label: nil)
}
