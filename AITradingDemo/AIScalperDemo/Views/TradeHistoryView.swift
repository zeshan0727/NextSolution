import SwiftUI

struct TradeHistoryView: View {
    @ObservedObject var engine: PaperTradingEngine

    var body: some View {
        ZStack {
            AppBackground()

            if engine.tradeHistory.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(.cyan)
                    Text("No Completed Trades")
                        .font(.title3.bold())
                    Text("Enable automatic paper trading or place a manual demo trade.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                }
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        summary

                        LazyVStack(spacing: 10) {
                            ForEach(engine.tradeHistory) { trade in
                                TradeHistoryRow(trade: trade)
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Trade History")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summary: some View {
        HStack(spacing: 10) {
            MetricTile(
                title: "Win rate",
                value: String(format: "%.0f%%", engine.winRate),
                systemImage: "scope",
                color: .purple
            )
            MetricTile(
                title: "Trades",
                value: "\(engine.tradeHistory.count)",
                systemImage: "arrow.left.arrow.right",
                color: .cyan
            )
        }
    }
}

private struct TradeHistoryRow: View {
    let trade: PaperTrade

    var body: some View {
        CardContainer {
            HStack(spacing: 12) {
                Image(systemName: trade.direction.icon)
                    .font(.headline.bold())
                    .foregroundStyle(trade.direction.color)
                    .frame(width: 42, height: 42)
                    .background(trade.direction.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(trade.asset.rawValue)
                            .font(.subheadline.bold())
                        Text(trade.direction.rawValue)
                            .font(.caption2.bold())
                            .foregroundStyle(trade.direction.color)
                    }
                    Text(trade.exitReason?.rawValue ?? "Completed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 5) {
                        Text(trade.dataSource?.rawValue ?? "Simulation v0.1")
                        if let fee = trade.feeCost, fee > 0 {
                            Text("• Fees \(fee.formatted(.currency(code: "USD")))")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    Text(trade.openedAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text((trade.profitLoss ?? 0).signedCurrency)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle((trade.profitLoss ?? 0) >= 0 ? .mint : .pink)
                    Text("\(trade.confidence)% signal")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
