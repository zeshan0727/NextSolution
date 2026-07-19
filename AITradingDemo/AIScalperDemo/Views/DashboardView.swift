import Charts
import SwiftUI

struct DashboardView: View {
    @ObservedObject var engine: PaperTradingEngine

    private var visibleCandles: [MarketCandle] {
        Array(engine.candles.suffix(55))
    }

    private var chartDomain: ClosedRange<Double> {
        let prices = visibleCandles.flatMap { [$0.low, $0.high] }
        let minimum = prices.min() ?? engine.currentPrice
        let maximum = prices.max() ?? engine.currentPrice
        let padding = max((maximum - minimum) * 0.18, engine.currentPrice * 0.00005)
        return (minimum - padding)...(maximum + padding)
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 16) {
                    demoBanner
                    accountSummary
                    marketCard
                    signalCard

                    if let trade = engine.openTrade {
                        OpenTradeCard(engine: engine, trade: trade)
                    } else {
                        manualTradeCard
                    }

                    safetyStatus
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("AI Scalper")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var demoBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text("PAPER TRADING ONLY")
                    .font(.caption.bold())
                    .foregroundStyle(.cyan)
                Text("Accelerated simulated market • no real orders")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.cyan.opacity(0.09), in: RoundedRectangle(cornerRadius: 15))
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .stroke(Color.cyan.opacity(0.22), lineWidth: 1)
        }
    }

    private var accountSummary: some View {
        HStack(spacing: 10) {
            MetricTile(
                title: "Demo balance",
                value: engine.balance.formatted(.currency(code: "USD")),
                systemImage: "dollarsign.circle.fill",
                color: .cyan
            )
            MetricTile(
                title: "Total P/L",
                value: engine.totalProfitLoss.signedCurrency,
                systemImage: engine.totalProfitLoss >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill",
                color: engine.totalProfitLoss >= 0 ? .mint : .pink
            )
        }
    }

    private var marketCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(engine.settings.asset.rawValue)
                            .font(.headline)
                        Text(engine.settings.asset.formattedPrice(engine.currentPrice))
                            .font(.system(size: 27, weight: .bold, design: .rounded))
                    }
                    Spacer()
                    LivePill()
                }

                Chart(visibleCandles) { candle in
                    AreaMark(
                        x: .value("Time", candle.time),
                        yStart: .value("Floor", chartDomain.lowerBound),
                        yEnd: .value("Price", candle.close)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan.opacity(0.24), .cyan.opacity(0.01)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Time", candle.time),
                        y: .value("Price", candle.close)
                    )
                    .foregroundStyle(.cyan)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                .chartYScale(domain: chartDomain)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing) { value in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                        AxisValueLabel {
                            if let price = value.as(Double.self) {
                                Text(engine.settings.asset.formattedPrice(price))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 190)
            }
        }
    }

    private var signalCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI SIGNAL")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(engine.indicators.signal.rawValue)
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundStyle(engine.indicators.signal.color)
                    }
                    Spacer()
                    ConfidenceRing(value: engine.indicators.confidence, color: engine.indicators.signal.color)
                }

                HStack(spacing: 8) {
                    IndicatorChip(title: "EMA", value: engine.indicators.ema9 > engine.indicators.ema21 ? "Bullish" : "Bearish")
                    IndicatorChip(title: "RSI", value: String(format: "%.1f", engine.indicators.rsi))
                    IndicatorChip(title: "MACD", value: engine.indicators.macd >= engine.indicators.macdSignal ? "+" : "−")
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(engine.indicators.reasons, id: \.self) { reason in
                        Label(reason, systemImage: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: Binding(
                    get: { engine.autoTradingEnabled },
                    set: { engine.setAutoTrading($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatic paper trading")
                            .font(.subheadline.bold())
                        Text("Enters only at \(engine.settings.confidenceThreshold)%+ confidence")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.cyan)
                .disabled(engine.isRiskLocked)
            }
        }
    }

    private var manualTradeCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Manual demo entry")
                            .font(.headline)
                        Text("Uses the same quick-profit and stop-loss rules")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(engine.settings.tradeAmount.formatted(.currency(code: "USD")))
                        .font(.subheadline.bold())
                }

                HStack(spacing: 10) {
                    TradeButton(direction: .buy) {
                        engine.openManual(.buy)
                    }
                    TradeButton(direction: .sell) {
                        engine.openManual(.sell)
                    }
                }
                .disabled(engine.isRiskLocked)
            }
        }
    }

    private var safetyStatus: some View {
        HStack(spacing: 10) {
            Image(systemName: engine.isRiskLocked ? "lock.fill" : "checkmark.shield.fill")
                .foregroundStyle(engine.isRiskLocked ? .pink : .mint)
            VStack(alignment: .leading, spacing: 2) {
                Text(engine.isRiskLocked ? "Trading locked by safety rules" : "Risk protection active")
                    .font(.subheadline.bold())
                Text("Today \(engine.todayProfitLoss.signedCurrency) • \(engine.consecutiveLosses) consecutive losses")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
    }
}
