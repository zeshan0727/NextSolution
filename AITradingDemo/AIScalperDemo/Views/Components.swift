import SwiftUI

struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.025, green: 0.045, blue: 0.085),
                Color(red: 0.015, green: 0.020, blue: 0.045)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

struct CardContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.075), Color.white.opacity(0.035)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 1)
            }
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.system(.headline, design: .rounded).bold().monospacedDigit())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 105, alignment: .leading)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(color.opacity(0.14), lineWidth: 1)
        }
    }
}

struct LivePill: View {
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.mint)
                .frame(width: 7, height: 7)
            Text("SIM LIVE")
                .font(.caption2.bold())
                .foregroundStyle(.mint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.mint.opacity(0.10), in: Capsule())
    }
}

struct ConfidenceRing: View {
    let value: Int
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 7)
            Circle()
                .trim(from: 0, to: Double(value) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(value)%")
                    .font(.headline.bold().monospacedDigit())
                Text("CONF")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 72, height: 72)
        .animation(.easeInOut(duration: 0.25), value: value)
    }
}

struct IndicatorChip: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.bold())
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct TradeButton: View {
    let direction: TradeDirection
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(direction.rawValue, systemImage: direction.icon)
                .font(.headline.bold())
                .foregroundStyle(Color.black.opacity(0.82))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(direction.color, in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open demo \(direction.rawValue) trade")
    }
}

struct OpenTradeCard: View {
    @ObservedObject var engine: PaperTradingEngine
    let trade: PaperTrade

    private var currentProfitLoss: Double {
        engine.unrealizedProfitLoss(for: trade)
    }

    private var progress: Double {
        min(1, Double(trade.ticksOpen) / Double(engine.settings.maxHoldingTicks))
    }

    var body: some View {
        CardContainer {
            VStack(spacing: 14) {
                HStack {
                    Label("OPEN \(trade.direction.rawValue)", systemImage: trade.direction.icon)
                        .font(.headline.bold())
                        .foregroundStyle(trade.direction.color)
                    Spacer()
                    Text(currentProfitLoss.signedCurrency)
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(currentProfitLoss >= 0 ? .mint : .pink)
                }

                HStack {
                    OpenTradeValue(title: "Entry", value: trade.asset.formattedPrice(trade.entryPrice))
                    Divider().frame(height: 34)
                    OpenTradeValue(title: "Current", value: trade.asset.formattedPrice(engine.currentPrice))
                    Divider().frame(height: 34)
                    OpenTradeValue(title: "Amount", value: trade.amount.formatted(.currency(code: "USD")))
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Timed exit")
                        Spacer()
                        Text("\(trade.ticksOpen)/\(engine.settings.maxHoldingTicks)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    ProgressView(value: progress)
                        .tint(.cyan)
                }

                Button(role: .destructive) {
                    engine.closeManually()
                } label: {
                    Text("Close demo trade now")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.bordered)
                .tint(.pink)
            }
        }
    }
}

private struct OpenTradeValue: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
    }
}

extension Double {
    var signedCurrency: String {
        let formatted = abs(self).formatted(.currency(code: "USD"))
        return self >= 0 ? "+\(formatted)" : "−\(formatted)"
    }
}
