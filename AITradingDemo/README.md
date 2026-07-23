# AI Scalper Demo

An iOS 16 SwiftUI paper-trading app designed for TrollStore testing. It never connects to a broker, accesses a trading account, or places real orders.

## Version 0.3

- Real one-minute candles plus Twelve Data WebSocket price ticks
- Major pairs: EUR/USD, GBP/USD, USD/JPY, USD/CHF, AUD/USD, USD/CAD, NZD/USD, EUR/GBP, and EUR/JPY
- Gold and BTC/USD remain available (XAU/USD depends on plan access)
- Secure API-key storage in the iPhone Keychain
- Immediate chart redraw for every genuine WebSocket tick
- Two-minute REST reconciliation/fallback while the app remains open
- Automatic stale-price lock that prevents entries on old candles
- Optional accelerated simulation for comparison with the original test
- EMA 9/21, RSI 14, Bollinger Bands 20/2, and MACD 12/26/9 signals
- Automatic or manual paper trades with quick take-profit, stop-loss, and timed exit
- Paper fills deduct estimated spread, adverse slippage, and round-trip fees
- Maximum daily loss and consecutive-loss safety locks
- Persistent paper balance, settings, and up to 500 completed trades

## Set up live market data

1. Create a Twelve Data account and API key at <https://twelvedata.com/pricing>.
2. Install and open AI Scalper Demo 0.3.
3. Open **Settings → Market data** and select **Live market**.
4. Paste the key and tap **Save key and connect**.
5. Select a supported pair and keep the app open while testing.

The key is stored in the device Keychain. It is sent only to Twelve Data over encrypted HTTPS/WSS connections. Twelve Data's free Basic plan has trial WebSocket access; if streaming is unavailable for a selected symbol, the app clearly shows that it is using REST fallback. Provider and daily request limits still apply.

Forex streaming does not mean millisecond forex quotes. Twelve Data currently documents mid-price updates around once per minute for its Forex API v2. The UI renders every real event immediately and never invents movement between provider updates. Crypto tick frequency can be higher.

## Trading-cost model

The cost values are conservative paper assumptions, not quotes from a broker:

| Asset | Spread | Maximum slippage per side | Fee per side |
|---|---:|---:|---:|
| EUR/USD | 0.012% | 0.006% | 0.010% |
| Gold | 0.025% | 0.010% | 0.015% |
| BTC/USD | 0.050% | 0.020% | 0.050% |

Actual spreads, slippage, commission, execution delay, rejected orders, and leverage can be substantially different.

## Build a TIPA on GitHub

1. Upload this folder and `.github/workflows/build-ai-scalper-tipa.yml` to a GitHub repository.
2. Open **Actions → Build AI Scalper TIPA → Run workflow**.
3. Download the `AI-Scalper-Demo-TrollStore` artifact.
4. Open `AI-Scalper-Demo.tipa` with TrollStore.

No Apple Developer account is required for the unsigned TrollStore build.

## Build in Xcode

1. Install XcodeGen: `brew install xcodegen`
2. Run `xcodegen generate` in this folder.
3. Open `AIScalperDemo.xcodeproj` and build the `AIScalperDemo` scheme.

Minimum deployment target: iOS 16.0.

## Important limitation

A high synthetic or live-feed paper win rate does not prove profitability. The signal rules are deterministic indicators, not a trained predictive AI model. Use this app only to collect evidence before considering any broker integration.
