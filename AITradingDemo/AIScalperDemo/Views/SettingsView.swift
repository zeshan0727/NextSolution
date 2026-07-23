import SwiftUI

struct SettingsView: View {
    @ObservedObject var engine: PaperTradingEngine
    @State private var showResetConfirmation = false
    @State private var apiKeyDraft = ""
    @State private var keyMessage: String?

    var body: some View {
        ZStack {
            AppBackground()

            Form {
                Section("Market data") {
                    Picker("Price source", selection: $engine.marketMode) {
                        ForEach(MarketDataMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(engine.openTrade != nil)

                    Picker("Asset", selection: $engine.settings.asset) {
                        ForEach(AssetSymbol.allCases) { asset in
                            Text(asset.rawValue).tag(asset)
                        }
                    }
                    .disabled(engine.openTrade != nil)

                    if engine.openTrade != nil {
                        Text("Close the current paper trade before changing its price source or asset.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if engine.marketMode == .live {
                        SecureField("Twelve Data API key", text: $apiKeyDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Button {
                            if engine.saveAPIKey(apiKeyDraft) {
                                apiKeyDraft = ""
                                keyMessage = "Key saved securely. Connecting now."
                            } else {
                                keyMessage = "Could not save that key. Check it and try again."
                            }
                        } label: {
                            Label(engine.hasAPIKey ? "Replace key and reconnect" : "Save key and connect", systemImage: "key.fill")
                        }
                        .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if engine.hasAPIKey {
                            Label("An API key is saved in this iPhone's Keychain", systemImage: "checkmark.shield.fill")
                                .font(.caption)
                                .foregroundStyle(.mint)

                            Button("Remove saved API key", role: .destructive) {
                                engine.clearAPIKey()
                                keyMessage = "Saved key removed."
                            }
                        }

                        if let keyMessage {
                            Text(keyMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let error = engine.lastFeedError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.pink)
                        } else {
                            Text("Status: \(engine.feedStatusText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Link(destination: URL(string: "https://twelvedata.com/pricing")!) {
                            Label("Create a Twelve Data API key", systemImage: "arrow.up.right.square")
                        }

                        Text("The key stays on this device. WebSocket mode redraws the chart on every genuine provider tick; REST candles reconcile every two minutes. Keep the app open while testing.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Twelve Data Basic includes only trial WebSocket access. Unsupported pairs automatically continue with the slower REST feed; full symbol streaming requires a compatible plan.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if engine.settings.asset == .gold {
                            Text("XAU/USD availability depends on your Twelve Data plan. EUR/USD or BTC/USD are the safest free-plan tests.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
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
                    if engine.marketMode == .live {
                        Stepper(
                            "Timed exit: \(engine.executionSettings.maxHoldingMinutes) minutes",
                            value: $engine.executionSettings.maxHoldingMinutes,
                            in: 1...10
                        )
                    } else {
                        Stepper(
                            "Timed exit: \(engine.settings.maxHoldingTicks) demo ticks",
                            value: $engine.settings.maxHoldingTicks,
                            in: 8...60,
                            step: 4
                        )
                    }

                    Label("Spread, adverse slippage and round-trip fees are deducted", systemImage: "minus.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

                Section("Paper account") {
                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        Label("Reset demo account", systemImage: "arrow.counterclockwise")
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("AI Scalper Demo 0.3")
                            .font(.subheadline.bold())
                        Text("Live mode uses real prices but every order and fill remains virtual. Results do not predict real trading performance.")
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
