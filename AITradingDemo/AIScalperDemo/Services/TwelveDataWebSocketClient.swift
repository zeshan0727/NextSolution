import Foundation

struct LivePriceTick {
    let symbol: String
    let price: Double
    let marketTime: Date
}

struct TwelveDataWebSocketClient {
    static func stream(
        symbol: String,
        apiKey: String,
        onConnected: @escaping @MainActor (String) -> Void,
        onTick: @escaping @MainActor (LivePriceTick) -> Void
    ) async throws {
        var components = URLComponents(string: "wss://ws.twelvedata.com/v1/quotes/price")
        components?.queryItems = [URLQueryItem(name: "apikey", value: apiKey)]
        guard let url = components?.url else { throw TwelveDataError.invalidURL }

        let socket = URLSession.shared.webSocketTask(with: url)
        socket.resume()

        let subscribe: [String: Any] = [
            "action": "subscribe",
            "params": ["symbols": symbol]
        ]
        let subscribeData = try JSONSerialization.data(withJSONObject: subscribe)
        guard let subscribeText = String(data: subscribeData, encoding: .utf8) else {
            throw TwelveDataError.invalidResponse
        }
        try await socket.send(.string(subscribeText))

        let heartbeat = Task {
            while !Task.isCancelled {
                try await Task.sleep(nanoseconds: 10_000_000_000)
                let message = "{\"action\":\"heartbeat\"}"
                try await socket.send(.string(message))
            }
        }

        defer {
            heartbeat.cancel()
            socket.cancel(with: .goingAway, reason: nil)
        }

        while !Task.isCancelled {
            let message = try await socket.receive()
            let data: Data
            switch message {
            case .string(let text):
                guard let value = text.data(using: .utf8) else { continue }
                data = value
            case .data(let value):
                data = value
            @unknown default:
                continue
            }

            guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let event = payload["event"] as? String else { continue }

            if event == "subscribe-status" {
                let status = (payload["status"] as? String)?.lowercased() ?? ""
                if status == "ok" || status == "success" {
                    await onConnected("Real-time tick stream connected")
                } else if status == "error" || status == "failed" {
                    let message = streamErrorMessage(from: payload)
                    throw TwelveDataError.serverMessage(message)
                }
                continue
            }

            guard event == "price",
                  let receivedSymbol = payload["symbol"] as? String,
                  receivedSymbol == symbol,
                  let price = doubleValue(payload["price"]),
                  let timestamp = doubleValue(payload["timestamp"]) else { continue }

            await onTick(LivePriceTick(
                symbol: receivedSymbol,
                price: price,
                marketTime: Date(timeIntervalSince1970: timestamp)
            ))
        }
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func streamErrorMessage(from payload: [String: Any]) -> String {
        if let message = payload["message"] as? String { return message }
        if let fails = payload["fails"] as? [[String: Any]],
           let first = fails.first {
            return (first["message"] as? String)
                ?? (first["symbol"] as? String).map { "Streaming is unavailable for \($0) on this API plan." }
                ?? "The WebSocket subscription was rejected."
        }
        return "The WebSocket subscription was rejected by Twelve Data."
    }
}
