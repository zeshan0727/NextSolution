import Foundation

enum BrowserURLDistribution {
    static let requiredURLCount = 4

    static func cleanedURLs(from inputs: [String]) -> [String]? {
        guard inputs.count == requiredURLCount else { return nil }
        let cleaned = inputs.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard cleaned.allSatisfy({ !$0.isEmpty }) else { return nil }
        return cleaned
    }

    static func assignments(
        for urls: [String],
        browserCount: Int = BrowserProfileStore.profileCount
    ) -> [String] {
        var generator = SystemRandomNumberGenerator()
        return assignments(for: urls, browserCount: browserCount, using: &generator)
    }

    static func assignments<R: RandomNumberGenerator>(
        for urls: [String],
        browserCount: Int,
        using generator: inout R
    ) -> [String] {
        guard !urls.isEmpty, browserCount > 0 else { return [] }
        var result = (0..<browserCount).map { urls[$0 % urls.count] }
        result.shuffle(using: &generator)
        return result
    }
}
