import Foundation

enum TwelveDataError: LocalizedError {
    case invalidURL
    case serverMessage(String)
    case invalidResponse
    case insufficientData

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The market-data request could not be created."
        case .serverMessage(let message):
            return message
        case .invalidResponse:
            return "Twelve Data returned an unreadable response."
        case .insufficientData:
            return "Not enough one-minute candles were returned for analysis."
        }
    }
}

struct TwelveDataClient {
    private struct APIResponse: Decodable {
        let values: [APIValue]?
        let status: String?
        let message: String?
    }

    private struct APIValue: Decodable {
        let datetime: String
        let open: String
        let high: String
        let low: String
        let close: String
    }

    static func fetchCandles(symbol: String, apiKey: String) async throws -> [MarketCandle] {
        var components = URLComponents(string: "https://api.twelvedata.com/time_series")
        components?.queryItems = [
            URLQueryItem(name: "symbol", value: symbol),
            URLQueryItem(name: "interval", value: "1min"),
            URLQueryItem(name: "outputsize", value: "80"),
            URLQueryItem(name: "order", value: "ASC"),
            URLQueryItem(name: "timezone", value: "UTC"),
            URLQueryItem(name: "apikey", value: apiKey)
        ]
        guard let url = components?.url else { throw TwelveDataError.invalidURL }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw TwelveDataError.invalidResponse
        }

        let decoded: APIResponse
        do {
            decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        } catch {
            throw TwelveDataError.invalidResponse
        }

        if decoded.status == "error" {
            throw TwelveDataError.serverMessage(decoded.message ?? "Twelve Data rejected the request.")
        }

        guard let values = decoded.values else { throw TwelveDataError.invalidResponse }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let candles = values.compactMap { value -> MarketCandle? in
            guard let time = formatter.date(from: value.datetime),
                  let open = Double(value.open),
                  let high = Double(value.high),
                  let low = Double(value.low),
                  let close = Double(value.close) else { return nil }
            return MarketCandle(time: time, open: open, high: high, low: low, close: close)
        }
        .sorted { $0.time < $1.time }

        guard candles.count >= 26 else { throw TwelveDataError.insufficientData }
        return candles
    }
}
