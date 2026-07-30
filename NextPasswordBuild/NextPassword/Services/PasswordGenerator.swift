import Foundation

enum PasswordGenerator {
    static func websiteBased(site: String) -> String {
        let cleaned = site
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { $0.isLetter || $0.isNumber }

        let letters = cleaned.filter(\.isLetter)
        let first = letters.first.map { String($0).uppercased() } ?? "X"
        let second: String
        if letters.count > 1 {
            second = String(letters[letters.index(after: letters.startIndex)]).lowercased()
        } else {
            second = "x"
        }

        let stableNumber = cleaned.unicodeScalars.reduce(0) { value, scalar in
            (value * 31 + Int(scalar.value)) % 100
        }
        let digits = String(format: "%02d", stableNumber)

        return "MpMr@\(first)\(second)\(digits)"
    }
}
