import SwiftUI

struct SettingsView: View {
    @ObservedObject var engine: PaperTradingEngine
    @State private var showResetConfirmation = false

    var body: some View {
        ZStack {
            AppBackground()

            Form {
                Section("Market") {
                    Picker("Demo asset", selection: $engine.settings.asset) {
                        ForEach(AssetSymbol.allCases) { asset in
                            Text(asset.rawValue).tag(asset)
                        }
                    }
                    .disabled(engine.openTrade != nil)

                    if engine.openTrade != nil {
                        Text("Close the current demo trade before changing the asset.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section("Position") {
                    AmountSlider(
                        title: "Trade amount",
                        value: $engine.settings.tradeAmount,
                        range: 5...100,
                        step: 5,
                        suffix: "USD"
                    )
                    AmountSlider(
                        title: "Quick take-profit",
                        value: $engine.settings.takeProfitPercent,
                        range: 0.20...2.00,
                        step: 0.10,
                        suffix: "%"
                    )
                    AmountSlider(
                        title: "Stop-loss",
                        value: $engine.settings.stopLossPercent,
                        range: 0.20...2.00,
                        step: 0.10,
                        suffix: "%"
                    )
                    Stepper(
                        "Timed exit: \(engine.settings.maxHoldingTicks) demo ticks",
                        value: $engine.settings.maxHoldingTicks,
                        in: 8...60,
                        step: 4
                    )
                }

                Section("AI confirmation") {
                    Stepper(
                        "Minimum confidence: \(engine.settings.confidenceThreshold)%",
                        value: $engine.settings.confidenceThreshold,
                        in: 60...90,
                        step: 2
                    )
                    Text("EMA 9/21, RSI 14, Bollinger Bands 20/2 and MACD 12/26/9 must agree before an automatic entry.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Safety lock") {
                    AmountSlider(
                        title: "Maximum daily loss",
                        value: $engine.settings.maxDailyLoss,
                        range: 10...100,
                        step: 5,
                        suffix: "USD"
                    )
                    Stepper(
                        "Stop after \(engine.settings.maxConsecutiveLosses) losses",
                        value: $engine.settings.maxConsecutiveLosses,
                        in: 1...6
                    )
                    Label("Martingale is not used", systemImage: "checkmark.shield.fill")
                        .foregroundStyle(.mint)
                }

                Section("Demo data") {
                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        Label("Reset demo account", systemImage: "arrow.counterclockwise")
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("AI Scalper Demo 0.1")
                            .font(.subheadline.bold())
                        Text("Simulation only. Prices, fills and results are generated on the device and do not represent real execution.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Reset all demo results?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Demo", role: .destructive) {
                engine.resetDemo()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The balance, trade history and safety lock will be reset.")
        }
    }
}

private struct AmountSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let suffix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(displayValue)
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(.cyan)
            }
            Slider(value: $value, in: range, step: step)
                .tint(.cyan)
        }
        .padding(.vertical, 4)
    }

    private var displayValue: String {
        if suffix == "%" {
            return String(format: "%.2f%%", value)
        }
        return String(format: "$%.0f", value)
    }
}
