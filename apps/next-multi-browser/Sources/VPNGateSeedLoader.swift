import Foundation

enum VPNGateSeedLoader {
    static func load() -> [VPNGateServer] {
        guard let url = Bundle.main.url(forResource: "VPNGateSeed", withExtension: "csv"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            return []
        }

        var servers: [VPNGateServer] = []
        for rawLine in text.split(whereSeparator: \Character.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("*") else { continue }
            let fields = parseCSVLine(line)
            guard fields.count >= 15 else { continue }

            let base64 = fields[14].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !base64.isEmpty,
                  Data(base64Encoded: base64, options: [.ignoreUnknownCharacters]) != nil else { continue }

            servers.append(VPNGateServer(
                hostName: fields[0],
                ipAddress: fields[1],
                score: Int(fields[2]) ?? 0,
                ping: Int(fields[3]),
                speed: Int64(fields[4]) ?? 0,
                countryName: fields[5].isEmpty ? fields[6] : fields[5],
                countryCode: fields[6].uppercased(),
                sessions: Int(fields[7]) ?? 0,
                uptime: Int64(fields[8]) ?? 0,
                configBase64: base64
            ))
        }

        return servers.sorted {
            if $0.countryName == $1.countryName {
                if $0.score == $1.score { return $0.speed > $1.speed }
                return $0.score > $1.score
            }
            return $0.countryName.localizedCaseInsensitiveCompare($1.countryName) == .orderedAscending
        }
    }

    private static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var insideQuotes = false
        var index = line.startIndex

        while index < line.endIndex {
            let character = line[index]
            if character == "\"" {
                let next = line.index(after: index)
                if insideQuotes, next < line.endIndex, line[next] == "\"" {
                    current.append("\"")
                    index = line.index(after: next)
                    continue
                }
                insideQuotes.toggle()
            } else if character == ",", !insideQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index = line.index(after: index)
        }
        fields.append(current)
        return fields
    }
}
