import Foundation

final class PaperTradingEngine: ObservableObject {
    @Published private(set) var candles: [MarketCandle] = []
    @Published private(set) var indicators = IndicatorSnapshot()
    @Published private(set) var openTrade: PaperTrade?
    @Published private(set) var tradeHistory: [PaperTrade] = []
    @Published private(set) var balance: Double = 1_000
    @Published private(set) var isRiskLocked = false
    @Published var autoTradingEnabled = false
    @Published var settings: StrategySettings {
        didSet {
            persistSettings()
            if oldValue.asset != settings.asset {
                resetMarket(for: settings.asset)
            }
        }
    }

    private var tickNumber = 0
    private var lastEntryTick = -100
    private let settingsKey = "ai-scalper.settings.v1"
    private let tradesKey = "ai-scalper.trades.v1"
    private let balanceKey = "ai-scalper.balance.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let saved = try? JSONDecoder().decode(StrategySettings.self, from: data) {
            settings = saved
        } else {
            settings = StrategySettings()
        }

        if let data = UserDefaults.standard.data(forKey: tradesKey),
           let saved = try? JSONDecoder().decode([PaperTrade].self, from: data) {
            tradeHistory = saved
        }

        if UserDefaults.standard.object(forKey: balanceKey) != nil {
            balance = UserDefaults.standard.double(forKey: balanceKey)
        } else {
            balance = settings.startingBalance
        }

        seedMarket(for: settings.asset)
        evaluateRiskLock()
    }

    var currentPrice: Double {
        candles.last?.close ?? settings.asset.basePrice
    }

    var totalProfitLoss: Double {
        balance - settings.startingBalance
    }

    var todayProfitLoss: Double {
        tradeHistory
            .filter { trade in
                guard let closedAt = trade.closedAt else { return false }
                return Calendar.current.isDateInToday(closedAt)
            }
            .compactMap(\.profitLoss)
            .reduce(0, +)
    }

    var winRate: Double {
        let closed = tradeHistory.filter { !$0.isOpen }
        guard !closed.isEmpty else { return 0 }
        let winners = closed.filter(\.isWinner).count
        return Double(winners) / Double(closed.count) * 100
    }

    var consecutiveLosses: Int {
        var losses = 0
        for trade in tradeHistory.sorted(by: { ($0.closedAt ?? .distantPast) > ($1.closedAt ?? .distantPast) }) {
            if trade.isWinner { break }
            losses += 1
        }
        return losses
    }

    func advanceMarket() {
        tickNumber += 1
        let previous = currentPrice
        let volatility = settings.asset.tickVolatility
        let noise = (Double.random(in: -1...1) + Double.random(in: -1...1) + Double.random(in: -1...1)) / 3
        let wave = sin(Double(tickNumber) / 17) * volatility * 0.30
        let movement = noise * volatility + wave
        let close = max(0.00001, previous * (1 + movement))
        let wick = previous * volatility * Double.random(in: 0.10...0.55)

        candles.append(MarketCandle(
            time: Date(),
            open: previous,
            high: max(previous, close) + wick,
            low: min(previous, close) - wick,
            close: close
        ))

        if candles.count > 240 {
            candles.removeFirst(candles.count - 240)
        }

        indicators = IndicatorEngine.analyse(candles: candles)
        updateOpenTrade()
        evaluateRiskLock()

        if autoTradingEnabled,
           !isRiskLocked,
           openTrade == nil,
           tickNumber - lastEntryTick >= 8,
           indicators.confidence >= settings.confidenceThreshold,
           let direction = indicators.signal.direction {
            open(direction: direction, confidence: indicators.confidence)
        }
    }

    func setAutoTrading(_ enabled: Bool) {
        if enabled && isRiskLocked { return }
        autoTradingEnabled = enabled
    }

    func openManual(_ direction: TradeDirection) {
        guard openTrade == nil, !isRiskLocked else { return }
        open(direction: direction, confidence: indicators.confidence)
    }

    func closeManually() {
        closeOpenTrade(reason: .manual)
    }

    func resetDemo() {
        autoTradingEnabled = false
        openTrade = nil
        tradeHistory = []
        balance = settings.startingBalance
        isRiskLocked = false
        tickNumber = 0
        lastEntryTick = -100
        persistTrades()
        persistBalance()
        resetMarket(for: settings.asset)
    }

    private func open(direction: TradeDirection, confidence: Int) {
        guard settings.tradeAmount > 0, settings.tradeAmount <= balance else { return }
        openTrade = PaperTrade(
            id: UUID(),
            asset: settings.asset,
            direction: direction,
            openedAt: Date(),
            entryPrice: currentPrice,
            amount: settings.tradeAmount,
            confidence: confidence,
            ticksOpen: 0
        )
        lastEntryTick = tickNumber
    }

    private func updateOpenTrade() {
        guard var trade = openTrade else { return }
        trade.ticksOpen += 1
        openTrade = trade

        let returnPercent = unrealizedReturnPercent(for: trade)
        if returnPercent >= settings.takeProfitPercent {
            closeOpenTrade(reason: .quickProfit)
        } else if returnPercent <= -settings.stopLossPercent {
            closeOpenTrade(reason: .stopLoss)
        } else if trade.ticksOpen >= settings.maxHoldingTicks {
            closeOpenTrade(reason: .timedExit)
        }
    }

    func unrealizedProfitLoss(for trade: PaperTrade) -> Double {
        trade.amount * unrealizedReturnPercent(for: trade) / 100
    }

    private func unrealizedReturnPercent(for trade: PaperTrade) -> Double {
        let rawMove = ((currentPrice - trade.entryPrice) / trade.entryPrice) * 100
        return rawMove * trade.direction.multiplier * trade.asset.demoLeverage
    }

    private func closeOpenTrade(reason: TradeExitReason) {
        guard var trade = openTrade else { return }
        let profitLoss = unrealizedProfitLoss(for: trade)
        trade.closedAt = Date()
        trade.exitPrice = currentPrice
        trade.profitLoss = profitLoss
        trade.exitReason = reason
        balance += profitLoss
        tradeHistory.insert(trade, at: 0)
        openTrade = nil
        persistTrades()
        persistBalance()
        evaluateRiskLock()
    }

    private func evaluateRiskLock() {
        let dailyLossHit = todayProfitLoss <= -settings.maxDailyLoss
        let lossStreakHit = consecutiveLosses >= settings.maxConsecutiveLosses
        isRiskLocked = dailyLossHit || lossStreakHit || balance <= 0
        if isRiskLocked {
            autoTradingEnabled = false
        }
    }

    private func resetMarket(for asset: AssetSymbol) {
        tickNumber = 0
        openTrade = nil
        seedMarket(for: asset)
    }

    private func seedMarket(for asset: AssetSymbol) {
        var price = asset.basePrice
        let now = Date()
        candles = (0..<80).map { index in
            let noise = Double.random(in: -1...1) * asset.tickVolatility
            let wave = sin(Double(index) / 9) * asset.tickVolatility * 0.45
            let open = price
            price = max(0.00001, price * (1 + noise + wave))
            let wick = open * asset.tickVolatility * 0.35
            return MarketCandle(
                time: now.addingTimeInterval(Double(index - 80) * 15),
                open: open,
                high: max(open, price) + wick,
                low: min(open, price) - wick,
                close: price
            )
        }
        indicators = IndicatorEngine.analyse(candles: candles)
    }

    private func persistSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: settingsKey)
    }

    private func persistTrades() {
        guard let data = try? JSONEncoder().encode(Array(tradeHistory.prefix(500))) else { return }
        UserDefaults.standard.set(data, forKey: tradesKey)
    }

    private func persistBalance() {
        UserDefaults.standard.set(balance, forKey: balanceKey)
    }
}
