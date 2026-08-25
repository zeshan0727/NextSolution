import Foundation

struct BrowserURLQueueBatch: Equatable {
    let urls: [String]
    let nextCursor: Int
    let totalCount: Int

    var isComplete: Bool { nextCursor >= totalCount }
}

struct BrowserURLQueueAssignment: Equatable {
    let browserIndex: Int
    let url: String
}

enum BrowserURLQueue {
    static let batchLimit = BrowserProfileStore.profileCount

    static func cleanedURLs(from pastedText: String) -> [String] {
        var seen = Set<String>()
        return pastedText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { value in
                guard !value.isEmpty, !seen.contains(value) else { return false }
                seen.insert(value)
                return true
            }
    }

    static func nextBatch(
        from urls: [String],
        cursor: Int,
        limit: Int = batchLimit
    ) -> BrowserURLQueueBatch? {
        guard !urls.isEmpty, limit > 0 else { return nil }
        let start = max(0, min(cursor, urls.count))
        guard start < urls.count else { return nil }
        let end = min(start + limit, urls.count)
        return BrowserURLQueueBatch(
            urls: Array(urls[start..<end]),
            nextCursor: end,
            totalCount: urls.count
        )
    }

    static func randomizedAssignments(
        for urls: [String],
        browserCount: Int = BrowserProfileStore.profileCount
    ) -> [BrowserURLQueueAssignment] {
        var generator = SystemRandomNumberGenerator()
        return randomizedAssignments(
            for: urls,
            browserCount: browserCount,
            using: &generator
        )
    }

    static func randomizedAssignments<R: RandomNumberGenerator>(
        for urls: [String],
        browserCount: Int,
        using generator: inout R
    ) -> [BrowserURLQueueAssignment] {
        guard !urls.isEmpty, browserCount > 0 else { return [] }
        let count = min(urls.count, browserCount)
        var shuffledURLs = Array(urls.prefix(count))
        shuffledURLs.shuffle(using: &generator)
        var browserIndices = Array(0..<browserCount)
        browserIndices.shuffle(using: &generator)
        return zip(browserIndices.prefix(count), shuffledURLs).map {
            BrowserURLQueueAssignment(browserIndex: $0.0, url: $0.1)
        }
    }
}
