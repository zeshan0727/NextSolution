import Foundation

final class PaperTradingEngine: ObservableObject {
    @Published private(set) var candles: [MarketCandle] = []
    @Published private(set) var indicators = IndicatorSnapshot()
    @Published private(set) var openTrade: PaperTrade?
    @Published private(set) var tradeHistory: [PaperTrade] = []
    @Published private(set) var balance: Double = 1_000
    @Published private(set) var isRiskLocked = false
    @Published private(set) var apiKey = ""
    @Published private(set) var feedState: FeedState = .simulated
    @Published private(set) var lastMarketUpdate: Date?
    @Published private(set) var lastFeedError: String?
    @Published var autoTradingEnabled = false

    @Published var marketMode: MarketDataMode {
        didSet {
            UserDefaults.standard.set(marketMode.rawValue, forKey: marketModeKey)
            prepareMarketForCurrentMode()
        }
    }

    @Published var executionSettings: ExecutionSettings {
        didSet { persistExecutionSettings() }
    }

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
    private let marketModeKey = "ai-scalper.market-mode.v2"
    private let executionSettingsKey = "ai-scalper.execution.v2"
    private let apiKeyAccount = "twelve-data-api-key"

    init() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let saved = try? JSONDecoder().decode(StrategySettings.self, from: data) {
            settings = saved
        } else {
            settings = StrategySettings()
        }

        if let data = UserDefaults.standard.data(forKey: executionSettingsKey),
           let saved = try? JSONDecoder().decode(ExecutionSettings.self, from: data) {
            executionSettings = saved
        } else {
            executionSettings = ExecutionSettings()
        }

        if let rawMode = UserDefaults.standard.string(forKey: marketModeKey),
           let savedMode = MarketDataMode(rawValue: rawMode) {
            marketMode = savedMode
        } else {
            marketMode = .live
        }

        apiKey = KeychainStore.read(account: apiKeyAccount) ?? ""

        if let data = UserDefaults.standard.data(forKey: tradesKey),
           let saved = try? JSONDecoder().decode([PaperTrade].self, from: data) {
            tradeHistory = saved
        }

        if UserDefaults.standard.object(forKey: balanceKey) != nil {
            balance = UserDefaults.standard.double(forKey: balanceKey)
        } else {
            balance = settings.startingBalance
        }

        if marketMode == .simulated {
            seedMarket(for: settings.asset)
            feedState = .simulated
        } else {
            feedState = apiKey.isEmpty ? .setupRequired : .connecting
        }
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

    var hasAPIKey: Bool { !apiKey.isEmpty }

    var isMarketReady: Bool {
        marketMode == .simulated || (feedState == .live && candles.count >= 26)
    }

    var feedTaskID: String {
        [marketMode.rawValue, settings.asset.apiSymbol, String(apiKey.hashValue), String(executionSettings.pollIntervalSeconds)]
            .joined(separator: "|")
    }

    var feedStatusText: String {
        switch feedState {
        case .setupRequired: return "API key required"
        case .connecting: return "Connecting"
        case .live: return "Live market data"
        case .error: return "Feed error"
        case .simulated: return "Accelerated simulation"
        }
    }

    @MainActor
    func runMarketFeed() async {
        guard marketMode == .live else { return }
        guard !apiKey.isEmpty else {
            feedState = .setupRequired
            lastFeedError = nil
            return
        }

        while !Task.isCancelled {
            feedState = candles.isEmpty ? .connecting : feedState
            do {
                let received = try await TwelveDataClient.fetchCandles(
                    symbol: settings.asset.apiSymbol,
                    apiKey: apiKey
                )
                guard !Task.isCancelled else { return }
                applyLiveCandles(received)
                feedState = .live
                lastFeedError = nil
                lastMarketUpdate = Date()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                feedState = .error
                lastFeedError = error.localizedDescription
                autoTradingEnabled = false
            }

            do {
                let delay = max(15, executionSettings.pollIntervalSeconds)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
        }
    }

    func saveAPIKey(_ newValue: String) -> Bool {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard KeychainStore.save(trimmed, account: apiKeyAccount) else { return false }
        apiKey = trimmed
        lastFeedError = nil
        feedState = .connecting
        return true
    }

    func clearAPIKey() {
        KeychainStore.delete(account: apiKeyAccount)
        apiKey = ""
        autoTradingEnabled = false
        lastFeedError = nil
        candles = []
        indicators = IndicatorSnapshot()
        feedState = .setupRequired
    }

    func advanceMarket() {
        guard marketMode == .simulated else { return }
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

        processMarketUpdate()
    }

    func setAutoTrading(_ enabled: Bool) {
        if enabled && (!isMarketReady || isRiskLocked) { return }
        autoTradingEnabled = enabled
    }

    func openManual(_ direction: TradeDirection) {
        guard openTrade == nil, !isRiskLocked, isMarketReady else { return }
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
        prepareMarketForCurrentMode()
    }

    func unrealizedProfitLoss(for trade: PaperTrade) -> Double {
        let estimatedExit = executionPrice(
            midPrice: currentPrice,
            direction: trade.direction,
            isEntry: false,
            slippagePercent: estimatedSlippage(for: trade.asset)
        )
        return profitLoss(for: trade, exitPrice: estimatedExit)
    }

    private func applyLiveCandles(_ received: [MarketCandle]) {
        candles = Array(received.suffix(240))
        tickNumber += 1
        processMarketUpdate()
    }

    private func processMarketUpdate() {
        indicators = IndicatorEngine.analyse(candles: candles)
        updateOpenTrade()
        evaluateRiskLock()

        let entrySpacing = marketMode == .live ? 2 : 8
        if autoTradingEnabled,
           !isRiskLocked,
           isMarketReady,
           openTrade == nil,
           tickNumber - lastEntryTick >= entrySpacing,
           indicators.confidence >= settings.confidenceThreshold,
           let direction = indicators.signal.direction {
            open(direction: direction, confidence: indicators.confidence)
        }
    }

    private func open(direction: TradeDirection, confidence: Int) {
        guard settings.tradeAmount > 0, settings.tradeAmount <= balance else { return }
        let slippage = actualSlippage(for: settings.asset)
        let price = executionPrice(
            midPrice: currentPrice,
            direction: direction,
            isEntry: true,
            slippagePercent: slippage
        )
        let totalFees = executionSettings.applyTradingCosts
            ? settings.tradeAmount * settings.asset.commissionPercentPerSide / 100 * 2
            : 0

        openTrade = PaperTrade(
            id: UUID(),
            asset: settings.asset,
            direction: direction,
            openedAt: Date(),
            entryPrice: price,
            amount: settings.tradeAmount,
            confidence: confidence,
            ticksOpen: 0,
            dataSource: marketMode,
            spreadPercent: executionSettings.applyTradingCosts ? settings.asset.spreadPercent : 0,
            entrySlippagePercent: slippage,
            feeCost: totalFees
        )
        lastEntryTick = tickNumber
    }

    private func updateOpenTrade() {
        guard var trade = openTrade else { return }
        trade.ticksOpen += 1
        openTrade = trade

        let netReturnPercent = unrealizedProfitLoss(for: trade) / trade.amount * 100
        if netReturnPercent >= settings.takeProfitPercent {
            closeOpenTrade(reason: .quickProfit)
        } else if netReturnPercent <= -settings.stopLossPercent {
            closeOpenTrade(reason: .stopLoss)
        } else if marketMode == .live,
                  Date().timeIntervalSince(trade.openedAt) >= Double(executionSettings.maxHoldingMinutes * 60) {
            closeOpenTrade(reason: .timedExit)
        } else if marketMode == .simulated, trade.ticksOpen >= settings.maxHoldingTicks {
            closeOpenTrade(reason: .timedExit)
        }
    }

    private func profitLoss(for trade: PaperTrade, exitPrice: Double) -> Double {
        let rawMove = ((exitPrice - trade.entryPrice) / trade.entryPrice) * 100
        let leveragedReturn = rawMove * trade.direction.multiplier * trade.asset.demoLeverage
        return trade.amount * leveragedReturn / 100 - (trade.feeCost ?? 0)
    }

    private func closeOpenTrade(reason: TradeExitReason) {
        guard var trade = openTrade else { return }
        let exitSlippage = actualSlippage(for: trade.asset)
        let exitPrice = executionPrice(
            midPrice: currentPrice,
            direction: trade.direction,
            isEntry: false,
            slippagePercent: exitSlippage
        )
        let profitLoss = profitLoss(for: trade, exitPrice: exitPrice)
        trade.closedAt = Date()
        trade.exitPrice = exitPrice
        trade.exitSlippagePercent = exitSlippage
        trade.profitLoss = profitLoss
        trade.exitReason = reason
        balance += profitLoss
        tradeHistory.insert(trade, at: 0)
        openTrade = nil
        persistTrades()
        persistBalance()
        evaluateRiskLock()
    }

    private func executionPrice(
        midPrice: Double,
        direction: TradeDirection,
        isEntry: Bool,
        slippagePercent: Double
    ) -> Double {
        guard executionSettings.applyTradingCosts else { return midPrice }
        let side = isEntry ? direction.multiplier : -direction.multiplier
        let adverseCost = settings.asset.spreadPercent / 2 + slippagePercent
        return midPrice * (1 + side * adverseCost / 100)
    }

    private func actualSlippage(for asset: AssetSymbol) -> Double {
        guard executionSettings.applyTradingCosts else { return 0 }
        return Double.random(in: asset.maximumSlippagePercent * 0.20...asset.maximumSlippagePercent)
    }

    private func estimatedSlippage(for asset: AssetSymbol) -> Double {
        executionSettings.applyTradingCosts ? asset.maximumSlippagePercent * 0.60 : 0
    }

    private func evaluateRiskLock() {
        let dailyLossHit = todayProfitLoss <= -settings.maxDailyLoss
        let lossStreakHit = consecutiveLosses >= settings.maxConsecutiveLosses
        isRiskLocked = dailyLossHit || lossStreakHit || balance <= 0
        if isRiskLocked {
            autoTradingEnabled = false
        }
    }

    private func prepareMarketForCurrentMode() {
        autoTradingEnabled = false
        lastFeedError = nil
        lastMarketUpdate = nil
        tickNumber = 0
        lastEntryTick = -100

        if marketMode == .simulated {
            feedState = .simulated
            seedMarket(for: settings.asset)
        } else {
            candles = []
            indicators = IndicatorSnapshot()
            feedState = apiKey.isEmpty ? .setupRequired : .connecting
        }
    }

    private func resetMarket(for asset: AssetSymbol) {
        autoTradingEnabled = false
        tickNumber = 0
        lastEntryTick = -100
        lastMarketUpdate = nil
        lastFeedError = nil

        if marketMode == .simulated {
            feedState = .simulated
            seedMarket(for: asset)
        } else {
            candles = []
            indicators = IndicatorSnapshot()
            feedState = apiKey.isEmpty ? .setupRequired : .connecting
        }
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

    private func persistExecutionSettings() {
        guard let data = try? JSONEncoder().encode(executionSettings) else { return }
        UserDefaults.standard.set(data, forKey: executionSettingsKey)
    }

    private func persistTrades() {
        guard let data = try? JSONEncoder().encode(Array(tradeHistory.prefix(500))) else { return }
        UserDefaults.standard.set(data, forKey: tradesKey)
    }

    private func persistBalance() {
        UserDefaults.standard.set(balance, forKey: balanceKey)
    }
}
