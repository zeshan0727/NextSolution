import Foundation

enum IndicatorEngine {
    static func analyse(candles: [MarketCandle]) -> IndicatorSnapshot {
        let closes = candles.map(\.close)
        guard closes.count >= 26, let price = closes.last else {
            return IndicatorSnapshot()
        }

        let ema9 = ema(closes, period: 9)
        let ema21 = ema(closes, period: 21)
        let currentRSI = rsi(closes, period: 14)
        let bands = bollingerBands(closes, period: 20, multiplier: 2)
        let macdLine = ema(closes, period: 12) - ema(closes, period: 26)

        let macdSeries = rollingMACD(closes)
        let macdSignal = ema(macdSeries, period: min(9, macdSeries.count))
        let histogram = macdLine - macdSignal

        var buyScore = 0
        var sellScore = 0
        var buyReasons: [String] = []
        var sellReasons: [String] = []

        if ema9 > ema21 {
            buyScore += 28
            buyReasons.append("EMA 9 is above EMA 21")
        } else {
            sellScore += 28
            sellReasons.append("EMA 9 is below EMA 21")
        }

        if currentRSI < 42 {
            buyScore += 27
            buyReasons.append("RSI shows an oversold recovery area")
        } else if currentRSI > 58 {
            sellScore += 27
            sellReasons.append("RSI shows an overbought reversal area")
        } else {
            buyScore += currentRSI >= 50 ? 9 : 0
            sellScore += currentRSI < 50 ? 9 : 0
        }

        if price < bands.lower {
            buyScore += 24
            buyReasons.append("Price touched the lower Bollinger Band")
        } else if price > bands.upper {
            sellScore += 24
            sellReasons.append("Price touched the upper Bollinger Band")
        } else if price >= bands.middle {
            buyScore += 12
        } else {
            sellScore += 12
        }

        if histogram > 0 {
            buyScore += 21
            buyReasons.append("MACD momentum is positive")
        } else {
            sellScore += 21
            sellReasons.append("MACD momentum is negative")
        }

        let difference = abs(buyScore - sellScore)
        let signal: SignalKind
        let confidence: Int
        let reasons: [String]

        if difference < 20 {
            signal = .wait
            confidence = min(69, 48 + difference)
            reasons = ["Indicators are mixed", "Waiting for stronger confirmation"]
        } else if buyScore > sellScore {
            signal = .buy
            confidence = min(94, 58 + difference / 2)
            reasons = Array(buyReasons.prefix(3))
        } else {
            signal = .sell
            confidence = min(94, 58 + difference / 2)
            reasons = Array(sellReasons.prefix(3))
        }

        return IndicatorSnapshot(
            ema9: ema9,
            ema21: ema21,
            rsi: currentRSI,
            bollingerUpper: bands.upper,
            bollingerMiddle: bands.middle,
            bollingerLower: bands.lower,
            macd: macdLine,
            macdSignal: macdSignal,
            signal: signal,
            confidence: confidence,
            reasons: reasons.isEmpty ? ["Momentum confirmation"] : reasons
        )
    }

    private static func ema(_ values: [Double], period: Int) -> Double {
        guard !values.isEmpty else { return 0 }
        let safePeriod = max(1, min(period, values.count))
        let multiplier = 2.0 / Double(safePeriod + 1)
        var result = values.prefix(safePeriod).reduce(0, +) / Double(safePeriod)

        for value in values.dropFirst(safePeriod) {
            result = ((value - result) * multiplier) + result
        }
        return result
    }

    private static func rsi(_ values: [Double], period: Int) -> Double {
        guard values.count > period else { return 50 }
        let recent = Array(values.suffix(period + 1))
        var gains = 0.0
        var losses = 0.0

        for index in 1..<recent.count {
            let change = recent[index] - recent[index - 1]
            if change >= 0 {
                gains += change
            } else {
                losses += abs(change)
            }
        }

        if losses == 0 { return 100 }
        let relativeStrength = (gains / Double(period)) / (losses / Double(period))
        return 100 - (100 / (1 + relativeStrength))
    }

    private static func bollingerBands(
        _ values: [Double],
        period: Int,
        multiplier: Double
    ) -> (upper: Double, middle: Double, lower: Double) {
        let recent = Array(values.suffix(period))
        guard !recent.isEmpty else { return (0, 0, 0) }
        let mean = recent.reduce(0, +) / Double(recent.count)
        let variance = recent.map { pow($0 - mean, 2) }.reduce(0, +) / Double(recent.count)
        let deviation = sqrt(variance)
        return (mean + deviation * multiplier, mean, mean - deviation * multiplier)
    }

    private static func rollingMACD(_ values: [Double]) -> [Double] {
        guard values.count >= 26 else { return [0] }
        return (26...values.count).map { endIndex in
            let slice = Array(values.prefix(endIndex))
            return ema(slice, period: 12) - ema(slice, period: 26)
        }
    }
}

