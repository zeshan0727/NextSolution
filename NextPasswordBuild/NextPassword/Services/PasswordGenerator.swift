import Foundation

enum PasswordGenerator {
    static func familiar(prefix: String, sequence: Int, extraLength: Int = 4) -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!#$%")
        let extra = String((0..<extraLength).compactMap { _ in chars.randomElement() })
        return "\(prefix)\(sequence)-\(extra)"
    }
}
