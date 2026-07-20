import Foundation
import SwiftUI

enum AssetSymbol: String, Codable, CaseIterable, Identifiable {
    case eurusd = "EUR/USD"
    case gbpusd = "GBP/USD"
    case usdjpy = "USD/JPY"
    case usdchf = "USD/CHF"
    case audusd = "AUD/USD"
    case usdcad = "USD/CAD"
    case nzdusd = "NZD/USD"
    case eurgbp = "EUR/GBP"
    case eurjpy = "EUR/JPY"
    case gold = "Gold"
    case bitcoin = "BTC/USD"

    var id: String { rawValue }

    var apiSymbol: String {
        switch self {
        case .eurusd: return "EUR/USD"
        case .gbpusd: return "GBP/USD"
        case .usdjpy: return "USD/JPY"
        case .usdchf: return "USD/CHF"
        case .audusd: return "AUD/USD"
        case .usdcad: return "USD/CAD"
        case .nzdusd: return "NZD/USD"
        case .eurgbp: return "EUR/GBP"
        case .eurjpy: return "EUR/JPY"
        case .gold: return "XAU/USD"
        case .bitcoin: return "BTC/USD"
        }
    }

    var isForex: Bool {
        self != .gold && self != .bitcoin
    }

    /// Conservative paper-fill assumptions. They can never reproduce a real
    /// broker exactly, but stop the demo from treating every mid-price as free.
    var spreadPercent: Double {
        switch self {
        case .eurusd: return 0.012
        case .gbpusd, .usdjpy, .usdchf, .audusd, .usdcad, .nzdusd: return 0.015
        case .eurgbp, .eurjpy: return 0.018
        case .gold: return 0.025
        case .bitcoin: return 0.050
        }
    }

    var maximumSlippagePercent: Double {
        switch self {
        case .eurusd: return 0.006
        case .gbpusd, .usdjpy, .usdchf, .audusd, .usdcad, .nzdusd, .eurgbp, .eurjpy: return 0.007
        case .gold: return 0.010
        case .bitcoin: return 0.020
        }
    }

    var commissionPercentPerSide: Double {
        switch self {
        case .eurusd, .gbpusd, .usdjpy, .usdchf, .audusd, .usdcad, .nzdusd, .eurgbp, .eurjpy: return 0.010
        case .gold: return 0.015
        case .bitcoin: return 0.050
        }
    }

    var basePrice: Double {
        switch self {
        case .eurusd: return 1.08520
        case .gbpusd: return 1.34120
        case .usdjpy: return 157.250
        case .usdchf: return 0.81240
        case .audusd: return 0.65210
        case .usdcad: return 1.37120
        case .nzdusd: return 0.59420
        case .eurgbp: return 0.80910
        case .eurjpy: return 170.640
        case .gold: return 2_420.00
        case .bitcoin: return 67_500.00
        }
    }

    var tickVolatility: Double {
        switch self {
        case .eurusd, .gbpusd, .usdjpy, .usdchf, .audusd, .usdcad, .nzdusd, .eurgbp, .eurjpy: return 0.000045
        case .gold: return 0.00022
        case .bitcoin: return 0.00042
        }
    }

    var demoLeverage: Double {
        switch self {
        case .eurusd, .gbpusd, .usdjpy, .usdchf, .audusd, .usdcad, .nzdusd, .eurgbp, .eurjpy: return 80
        case .gold: return 45
        case .bitcoin: return 25
        }
    }

    var precision: Int {
        switch self {
        case .usdjpy, .eurjpy: return 3
        case .eurusd, .gbpusd, .usdchf, .audusd, .usdcad, .nzdusd, .eurgbp: return 5
        case .gold: return 2
        case .bitcoin: return 2
        }
    }

    func formattedPrice(_ price: Double) -> String {
        String(format: "%.*f", precision, price)
    }
}

enum MarketDataMode: String, Codable, CaseIterable, Identifiable {
    case live = "Live market"
    case simulated = "Simulation"

    var id: String { rawValue }
    var shortLabel: String { self == .live ? "LIVE DATA" : "SIM LIVE" }
}

enum FeedState: String {
    case setupRequired
    case connecting
    case live
    case stale
    case error
    case simulated
}

enum TradeDirection: String, Codable, CaseIterable, Identifiable {
    case buy = "BUY"
    case sell = "SELL"

    var id: String { rawValue }
    var icon: String { self == .buy ? "arrow.up.right" : "arrow.down.right" }
    var color: Color { self == .buy ? .mint : .pink }
    var multiplier: Double { self == .buy ? 1 : -1 }
}

enum SignalKind: String, Codable {
    case buy = "BUY"
    case sell = "SELL"
    case wait = "WAIT"

    var direction: TradeDirection? {
        switch self {
        case .buy: return .buy
        case .sell: return .sell
        case .wait: return nil
        }
    }

    var color: Color {
        switch self {
        case .buy: return .mint
        case .sell: return .pink
        case .wait: return .orange
        }
    }
}

enum TradeExitReason: String, Codable {
    case quickProfit = "Quick profit"
    case stopLoss = "Stop loss"
    case timedExit = "Timed exit"
    case manual = "Manual close"
}

struct MarketCandle: Identifiable, Codable {
    let id: UUID
    let time: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double

    init(id: UUID = UUID(), time: Date, open: Double, high: Double, low: Double, close: Double) {
        self.id = id
        self.time = time
        self.open = open
        self.high = high
        self.low = low
        self.close = close
    }
}

struct IndicatorSnapshot {
    var ema9: Double = 0
    var ema21: Double = 0
    var rsi: Double = 50
    var bollingerUpper: Double = 0
    var bollingerMiddle: Double = 0
    var bollingerLower: Double = 0
    var macd: Double = 0
    var macdSignal: Double = 0
    var signal: SignalKind = .wait
    var confidence: Int = 0
    var reasons: [String] = ["Collecting market data"]
}

struct PaperTrade: Identifiable, Codable {
    let id: UUID
    let asset: AssetSymbol
    let direction: TradeDirection
    let openedAt: Date
    var closedAt: Date?
    let entryPrice: Double
    var exitPrice: Double?
    let amount: Double
    let confidence: Int
    var profitLoss: Double?
    var exitReason: TradeExitReason?
    var ticksOpen: Int
    var dataSource: MarketDataMode? = nil
    var spreadPercent: Double? = nil
    var entrySlippagePercent: Double? = nil
    var exitSlippagePercent: Double? = nil
    var feeCost: Double? = nil

    var isOpen: Bool { closedAt == nil }
    var isWinner: Bool { (profitLoss ?? 0) > 0 }
}

struct StrategySettings: Codable, Equatable {
    var asset: AssetSymbol = .eurusd
    var startingBalance: Double = 1_000
    var tradeAmount: Double = 25
    var takeProfitPercent: Double = 0.80
    var stopLossPercent: Double = 0.60
    var confidenceThreshold: Int = 72
    var maxDailyLoss: Double = 35
    var maxConsecutiveLosses: Int = 3
    var maxHoldingTicks: Int = 24
}

struct ExecutionSettings: Codable, Equatable {
    var pollIntervalSeconds: Double = 120
    var maxHoldingMinutes: Int = 3
    var applyTradingCosts = true
}
