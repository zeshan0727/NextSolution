import Foundation

extension LedgerStore {
    @discardableResult
    func backfillVendorRulesFromTransactions() -> Int {
        var knownKeywords = Set(
            settings.vendorRules.map {
                $0.keyword
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                    .lowercased()
            }
        )

        var additions: [VendorCategoryRule] = []

        for transaction in transactions where transaction.type != .transfer {
            let category = transaction.category.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isUsefulRecoveredCategory(category),
                  let keyword = recoveredVendorKeyword(for: transaction) else { continue }

            let normalized = keyword
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .lowercased()

            guard !knownKeywords.contains(normalized) else { continue }
            knownKeywords.insert(normalized)
            additions.append(VendorCategoryRule(keyword: keyword, category: category))
        }

        for rule in additions {
            saveVendorRule(rule)
        }

        return additions.count
    }

    private func isUsefulRecoveredCategory(_ category: String) -> Bool {
        guard !category.isEmpty else { return false }
        let blocked = ["transfer", "uncategorized", "z-ip-14pm-16.0", "other"]
        return !blocked.contains { category.caseInsensitiveCompare($0) == .orderedSame }
    }

    private func recoveredVendorKeyword(for transaction: LedgerTransaction) -> String? {
        var merchant = transaction.vendor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if merchant.isEmpty {
            let pattern = #"\bat\s+(.+?)\s+at\s+\d{1,2}:\d{2}"#
            if let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = expression.firstMatch(
                    in: transaction.details,
                    range: NSRange(transaction.details.startIndex..., in: transaction.details)
               ),
               let range = Range(match.range(at: 1), in: transaction.details) {
                merchant = String(transaction.details[range])
            }
        }

        let ignored = Set([
            "al", "new", "the", "merchant", "store", "trading", "wll", "llc",
            "company", "co", "qatar", "doha", "branch", "payment", "card"
        ])

        let words = merchant
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 && !ignored.contains($0.lowercased()) }

        guard let first = words.first else { return nil }
        if words.count > 1 {
            return [first, words[1]].joined(separator: " ")
        }
        return first
    }
}
