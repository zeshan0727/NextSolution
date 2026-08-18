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

    var cleanURL: URL {
        if let absolute = URL(string: href), absolute.scheme != nil {
            return Self.cleaned(url: absolute)
        }

        let trimmed = href.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let withoutHTML = trimmed.hasSuffix(".html") ? String(trimmed.dropLast(5)) : trimmed
        return URL(string: "https://nextsolution.cc/\(withoutHTML)/")!
    }

    private static func cleaned(url: URL) -> URL {
        var value = url.absoluteString
        if value.hasSuffix(".html") {
            value = String(value.dropLast(5)) + "/"
        } else if !value.hasSuffix("/") {
            value += "/"
        }
        return URL(string: value) ?? url
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
