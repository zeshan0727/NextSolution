# AI Scalper Demo

An iOS 16 SwiftUI paper-trading simulator designed for TrollStore testing. It does not connect to a broker, access a trading account, or place real orders.

## Included in version 0.1

- Accelerated simulated prices for EUR/USD, Gold, and BTC/USD
- EMA 9/21, RSI 14, Bollinger Bands 20/2, and MACD 12/26/9 analysis
- BUY, SELL, or WAIT signals with a confidence score
- Automatic paper trades above the selected confidence threshold
- Quick take-profit, stop-loss, and timed exit
- Manual BUY/SELL demo buttons
- Maximum daily loss and consecutive-loss safety locks
- Persistent demo balance, settings, and up to 500 completed trades
- Dark, colourful iPhone interface optimized for iOS 16

## Important limitation

All prices and fills are generated locally. A profitable demo result does not demonstrate that the same strategy will be profitable with real market data, spread, commission, slippage, network delay, or rejected orders.

## Build a TIPA on GitHub

1. Create a new GitHub repository and upload everything in this folder.
2. Open the repository's **Actions** tab.
3. Select **Build TrollStore TIPA** and choose **Run workflow**.
4. When it finishes, download the `AI-Scalper-Demo-TrollStore` artifact.
5. Open `AI-Scalper-Demo.tipa` with TrollStore on the iPhone.

No Apple Developer account is required for the unsigned TrollStore build.

## Build in Xcode

1. Install XcodeGen: `brew install xcodegen`
2. Run `xcodegen generate` in this folder.
3. Open `AIScalperDemo.xcodeproj` and run the `AIScalperDemo` scheme.

Minimum deployment target: iOS 16.0.

