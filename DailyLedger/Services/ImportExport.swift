import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum ImportExportError: LocalizedError {
    case unsupportedFile
    case malformedCSV

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            return "This file is not a Next Ledger JSON backup or supported CSV file."
        case .malformedCSV:
            return "The CSV file does not contain recognizable Next Ledger transaction columns."
        }
    }
}

struct ImportPayload {
    let transactions: [LedgerTransaction]
    let accounts: [LedgerAccount]
    let settings: LedgerSettings?
}

enum ImportExportCodec {
    static func backupData(
        transactions: [LedgerTransaction],
        accounts: [LedgerAccount],
        settings: LedgerSettings
    ) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(
            LedgerData(version: 5, transactions: transactions, accounts: accounts, settings: settings)
        )) ?? Data()
    }

    static func csvData(transactions: [LedgerTransaction], accounts: [LedgerAccount]) -> Data {
        var rows = [[
            "id", "type", "amount", "destination_amount", "currency", "destination_currency",
            "date", "category", "vendor", "details", "account", "transfer_account"
        ]]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let accountLookup = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })

        rows.append(contentsOf: transactions.map { item in
            let source = item.accountID.flatMap { accountLookup[$0] }
            let destination = item.destinationAccountID.flatMap { accountLookup[$0] }
            return [
                item.id.uuidString,
                item.type.rawValue,
                NSDecimalNumber(decimal: item.amount).stringValue,
                item.destinationAmount.map { NSDecimalNumber(decimal: $0).stringValue } ?? "",
                source?.currencyCode ?? "",
                destination?.currencyCode ?? "",
                formatter.string(from: item.date),
                item.category,
                item.vendor ?? "",
                item.details,
                source?.name ?? "",
                destination?.name ?? ""
            ]
        })
        let text = rows.map { $0.map(escapeCSV).joined(separator: ",") }.joined(separator: "\n")
        return Data(text.utf8)
    }

    static func decode(url: URL) throws -> ImportPayload {
        try decode(data: Data(contentsOf: url))
    }

    static func decode(data: Data) throws -> ImportPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let ledger = try? decoder.decode(LedgerData.self, from: data) {
            return ImportPayload(
                transactions: ledger.transactions,
                accounts: ledger.accounts,
                settings: ledger.settings
            )
        }
        if let transactions = try? decoder.decode([LedgerTransaction].self, from: data) {
            return ImportPayload(transactions: transactions, accounts: [], settings: nil)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ImportExportError.unsupportedFile
        }
        return try decodeCSV(text)
    }

    static func decodeCSV(_ text: String) throws -> ImportPayload {
        let rows = parseCSV(text)
        guard let first = rows.first else { throw ImportExportError.malformedCSV }
        let header = first.map(normalizedHeader)
        return try decodeNextLedgerCSV(rows, header: header)
    }

    private static func decodeNextLedgerCSV(
        _ rows: [[String]],
        header: [String]
    ) throws -> ImportPayload {
        guard let typeIndex = header.firstIndex(of: "type"),
              let amountIndex = header.firstIndex(of: "amount"),
              let dateIndex = header.firstIndex(of: "date") else {
            throw ImportExportError.malformedCSV
        }

        let idIndex = header.firstIndex(of: "id")
        let destinationAmountIndex = header.firstIndex(of: "destination amount")
        let currencyIndex = header.firstIndex(of: "currency")
        let destinationCurrencyIndex = header.firstIndex(of: "destination currency")
        let categoryIndex = header.firstIndex(of: "category")
        let vendorIndex = header.firstIndex(of: "vendor") ?? header.firstIndex(of: "merchant")
        let detailsIndex = header.firstIndex(of: "details") ?? header.firstIndex(of: "note")
        let accountIndex = header.firstIndex(of: "account")
        let transferAccountIndex = header.firstIndex(of: "transfer account")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()

        var accountCurrencies: [String: String] = [:]
        var accountDisplayNames: [String: String] = [:]

        for row in rows.dropFirst() {
            let sourceName = value(row, at: accountIndex).trimmingCharacters(in: .whitespacesAndNewlines)
            let destinationName = value(row, at: transferAccountIndex).trimmingCharacters(in: .whitespacesAndNewlines)
            let sourceCurrency = normalizedCurrency(value(row, at: currencyIndex))
            let destinationCurrency = normalizedCurrency(value(row, at: destinationCurrencyIndex))

            if !sourceName.isEmpty {
                let key = sourceName.lowercased()
                accountDisplayNames[key] = accountDisplayNames[key] ?? sourceName
                if let sourceCurrency { accountCurrencies[key] = sourceCurrency }
            }
            if !destinationName.isEmpty {
                let key = destinationName.lowercased()
                accountDisplayNames[key] = accountDisplayNames[key] ?? destinationName
                if let destinationCurrency { accountCurrencies[key] = destinationCurrency }
            }
        }

        let accounts = accountDisplayNames.keys.sorted().map { key in
            genericImportedAccount(
                named: accountDisplayNames[key] ?? "Account",
                currencyCode: accountCurrencies[key] ?? "QAR"
            )
        }
        let accountsByName = Dictionary(uniqueKeysWithValues: accounts.map { ($0.name.lowercased(), $0) })

        let transactions = rows.dropFirst().enumerated().compactMap { offset, row -> LedgerTransaction? in
            guard row.indices.contains(typeIndex), row.indices.contains(amountIndex), row.indices.contains(dateIndex),
                  let type = TransactionType(rawValue: row[typeIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()),
                  let amount = decimal(row[amountIndex]),
                  let date = formatter.date(from: row[dateIndex]) ?? fallbackFormatter.date(from: row[dateIndex]) else {
                return nil
            }

            let id = idIndex.flatMap { row.indices.contains($0) ? UUID(uuidString: row[$0]) : nil }
                ?? stableUUID("next-ledger-csv|\(offset)|\(row.joined(separator: "|"))")
            let category = value(row, at: categoryIndex).nilIfBlank ?? (type == .transfer ? "Transfer" : "Other")
            let vendor = value(row, at: vendorIndex).nilIfBlank
            let details = value(row, at: detailsIndex)
            let sourceName = value(row, at: accountIndex).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let destinationName = value(row, at: transferAccountIndex).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let destinationAmount = value(row, at: destinationAmountIndex).nilIfBlank.flatMap(decimal)

            return LedgerTransaction(
                id: id,
                type: type,
                amount: abs(amount),
                date: date,
                category: category,
                vendor: vendor,
                details: details,
                accountID: sourceName.isEmpty ? nil : accountsByName[sourceName]?.id,
                destinationAccountID: destinationName.isEmpty ? nil : accountsByName[destinationName]?.id,
                destinationAmount: destinationAmount.map(abs)
            )
        }

        guard !transactions.isEmpty || rows.count == 1 else {
            throw ImportExportError.malformedCSV
        }
        return ImportPayload(transactions: transactions, accounts: accounts, settings: nil)
    }

    private static func genericImportedAccount(named name: String, currencyCode: String) -> LedgerAccount {
        LedgerAccount(
            id: stableUUID("next-ledger-account|\(name.lowercased())|\(currencyCode.uppercased())"),
            name: name,
            currencyCode: currencyCode.uppercased(),
            group: .other,
            icon: "creditcard.fill"
        )
    }

    private static func normalizedCurrency(_ value: String) -> String? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard cleaned.count == 3, cleaned.allSatisfy({ $0.isLetter }) else { return nil }
        return cleaned
    }

    private static func stableUUID(_ source: String) -> UUID {
        var first: UInt64 = 14_695_981_039_346_656_037
        var second: UInt64 = 10_995_116_282_111
        for byte in source.utf8 {
            first ^= UInt64(byte)
            first &*= 1_099_511_628_211
            second = (second &* 1_099_511_628_211) ^ UInt64(byte &+ 31)
        }
        let hex = String(format: "%016llx%016llx", first, second)
        let value = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-5\(hex.dropFirst(13).prefix(3))-a\(hex.dropFirst(17).prefix(3))-\(hex.dropFirst(20).prefix(12))"
        return UUID(uuidString: value) ?? UUID()
    }

    private static func normalizedHeader(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decimal(_ value: String) -> Decimal? {
        Decimal(
            string: value.replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private static func value(_ row: [String], at index: Int?) -> String {
        guard let index, row.indices.contains(index) else { return "" }
        return row[index]
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

private extension String {
    var nilIfBlank: String? {
        let cleaned = trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
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
