import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum ImportExportError: LocalizedError {
    case unsupportedFile
    case malformedCSV

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            return "This file is not a Daily Ledger JSON backup or supported CSV file."
        case .malformedCSV:
            return "The CSV file does not contain the required type, amount, and date columns."
        }
    }
}

struct ImportPayload {
    let transactions: [LedgerTransaction]
    let settings: LedgerSettings?
}

enum ImportExportCodec {
    static func backupData(transactions: [LedgerTransaction], settings: LedgerSettings) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(
            LedgerData(version: 2, transactions: transactions, settings: settings)
        )) ?? Data()
    }

    static func csvData(transactions: [LedgerTransaction], currencyCode: String) -> Data {
        var rows = [["id", "type", "amount", "currency", "date", "category", "vendor", "details"]]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        rows.append(contentsOf: transactions.map {
            [
                $0.id.uuidString,
                $0.type.rawValue,
                NSDecimalNumber(decimal: $0.amount).stringValue,
                currencyCode,
                formatter.string(from: $0.date),
                $0.category,
                $0.vendor ?? "",
                $0.details
            ]
        })
        let text = rows.map { $0.map(escapeCSV).joined(separator: ",") }.joined(separator: "\n")
        return Data(text.utf8)
    }

    static func decode(url: URL) throws -> ImportPayload {
        let data = try Data(contentsOf: url)
        if url.pathExtension.lowercased() == "json" {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let ledger = try? decoder.decode(LedgerData.self, from: data) {
                return ImportPayload(
                    transactions: ledger.transactions,
                    settings: ledger.settings
                )
            }
            if let transactions = try? decoder.decode([LedgerTransaction].self, from: data) {
                return ImportPayload(transactions: transactions, settings: nil)
            }
            throw ImportExportError.unsupportedFile
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ImportExportError.unsupportedFile
        }
        return ImportPayload(transactions: try decodeCSV(text), settings: nil)
    }

    static func decodeCSV(_ text: String) throws -> [LedgerTransaction] {
        let rows = parseCSV(text)
        guard let header = rows.first?.map({ $0.lowercased().trimmingCharacters(in: .whitespaces) }),
              let typeIndex = header.firstIndex(of: "type"),
              let amountIndex = header.firstIndex(of: "amount"),
              let dateIndex = header.firstIndex(of: "date") else {
            throw ImportExportError.malformedCSV
        }

        let idIndex = header.firstIndex(of: "id")
        let categoryIndex = header.firstIndex(of: "category")
        let vendorIndex = header.firstIndex(of: "vendor") ?? header.firstIndex(of: "merchant")
        let detailsIndex = header.firstIndex(of: "details") ?? header.firstIndex(of: "note")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()

        return rows.dropFirst().compactMap { row in
            guard row.indices.contains(typeIndex), row.indices.contains(amountIndex),
                  row.indices.contains(dateIndex),
                  let type = TransactionType(rawValue: row[typeIndex].lowercased()),
                  let amount = Decimal(
                    string: row[amountIndex],
                    locale: Locale(identifier: "en_US_POSIX")
                  ),
                  let date = formatter.date(from: row[dateIndex]) ?? fallbackFormatter.date(from: row[dateIndex]) else {
                return nil
            }
            let id = idIndex.flatMap { row.indices.contains($0) ? UUID(uuidString: row[$0]) : nil } ?? UUID()
            let category = categoryIndex.flatMap { row.indices.contains($0) ? row[$0] : nil } ?? "Other"
            let vendor = vendorIndex.flatMap { row.indices.contains($0) ? row[$0] : nil }
            let details = detailsIndex.flatMap { row.indices.contains($0) ? row[$0] : nil } ?? ""
            return LedgerTransaction(
                id: id,
                type: type,
                amount: amount,
                date: date,
                category: category.isEmpty ? "Other" : category,
                vendor: vendor?.isEmpty == false ? vendor : nil,
                details: details
            )
        }
    }

    private static func escapeCSV(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let characters = Array(text)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if inQuotes, index + 1 < characters.count, characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    inQuotes.toggle()
                }
            } else if character == ",", !inQuotes {
                row.append(field)
                field = ""
            } else if (character == "\n" || character == "\r"), !inQuotes {
                if character == "\r", index + 1 < characters.count, characters[index + 1] == "\n" {
                    index += 1
                }
                row.append(field)
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index += 1
        }
        row.append(field)
        if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        return rows
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
