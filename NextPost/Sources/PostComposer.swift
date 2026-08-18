import Foundation

struct PostComposer {
    static let maximumCharacters = 280

    func compose(for article: PublishedArticle) -> String {
        let link = article.socialShareURL.absoluteString
        var tags = hashtags(for: article)
        var header = "🚀 \(clean(article.title))"

        if header.count > 118 {
            let version = article.version.map { " \($0)" } ?? ""
            header = "🚀 \(clean(article.name))\(version)"
        }

        var footer = footerText(link: link, tags: tags)
        var available = Self.maximumCharacters - header.count - footer.count - 4

        while available < 36 && tags.count > 2 {
            tags.removeLast()
            footer = footerText(link: link, tags: tags)
            available = Self.maximumCharacters - header.count - footer.count - 4
        }

        var summary = trim(clean(article.description), to: max(0, available))
        var result = "\(header)\n\n\(summary)\n\n\(footer)"

        if result.count > Self.maximumCharacters {
            let overflow = result.count - Self.maximumCharacters
            summary = trim(summary, to: max(0, summary.count - overflow - 1))
            result = "\(header)\n\n\(summary)\n\n\(footer)"
        }

        return result
    }

    private func footerText(link: String, tags: [String]) -> String {
        "🔗 \(link)\n\(tags.joined(separator: " "))"
    }

    private func hashtags(for article: PublishedArticle) -> [String] {
        let combined = "\(article.title) \(article.description) \(article.category?.label ?? "")".lowercased()
        var tags: [String] = []

        if let nameTag = hashtag(article.name), nameTag.count <= 28 {
            tags.append(nameTag)
        }

        if combined.contains("jailbreak") || combined.contains("tweak") || combined.contains("rootless") {
            tags.append("#Jailbreak")
        } else {
            tags.append("#iOS")
        }

        if combined.contains("ios 17") || combined.contains("ios17") {
            tags.append("#iOS17")
        } else if combined.contains("ios 16") || combined.contains("ios16") {
            tags.append("#iOS16")
        } else {
            tags.append("#iPhone")
        }

        if combined.contains("rootless") {
            tags.append("#Rootless")
        } else if combined.contains("home screen") {
            tags.append("#HomeScreen")
        } else if combined.contains("lock screen") {
            tags.append("#LockScreen")
        } else if combined.contains("control center") {
            tags.append("#ControlCenter")
        } else if combined.contains("airpods") {
            tags.append("#AirPods")
        } else if combined.contains("keyboard") {
            tags.append("#Keyboard")
        }

        if !tags.contains("#iPhone") && tags.count < 4 {
            tags.append("#iPhone")
        }

        var seen = Set<String>()
        return tags.filter { seen.insert($0.lowercased()).inserted }.prefix(4).map { $0 }
    }

    private func hashtag(_ value: String) -> String? {
        let result = String(value.filter { $0.isLetter || $0.isNumber })
        guard result.count >= 2 else { return nil }
        return "#\(result)"
    }

    private func trim(_ value: String, to maxLength: Int) -> String {
        guard maxLength > 0 else { return "" }
        guard value.count > maxLength else { return value }
        guard maxLength > 1 else { return "…" }

        var cut = String(value.prefix(maxLength - 1))
        if let lastSpace = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: lastSpace) > maxLength / 2 {
            cut = String(cut[..<lastSpace])
        }
        cut = cut.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return cut + "…"
    }

    private func clean(_ value: String) -> String {
        value
            .replacingOccurrences(of: "##?", with: "details")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
