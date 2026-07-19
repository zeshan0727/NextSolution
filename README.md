# Daily Ledger

Daily Ledger is an offline personal income and expense tracker for iPhone. This build targets iOS 16.0 and is designed to be packaged as a `.tipa` for TrollStore.

## Included in version 1.1

- Fast income and expense entry with colorful categories
- Home dashboard with current balance and monthly totals
- Searchable transaction history grouped by date
- Tap any transaction to edit its amount, type, category, description, or date
- Monthly and yearly reports with income/expense charts
- Spending breakdown by category
- QAR default currency, plus USD, GBP, EUR, AED, SAR, PKR, and INR display options
- CSV export for Excel, Numbers, Zoho, and other apps
- Complete JSON backup export and merge-safe import
- Offline App Intents for Shortcuts:
  - Add Expense
  - Add Income
  - Open Expense Entry
  - Open Income Entry

Data is saved locally in the app's Application Support folder with protection that allows an approved Shortcut to write while the device is locked after the first unlock following a restart.

## Build the TIPA without a developer account

The included GitHub Actions workflow builds the unsigned iPhone app on macOS and packages it for TrollStore.

1. Upload this folder to a GitHub repository.
2. Open **Actions → Build Daily Ledger TIPA → Run workflow**.
3. Download the **DailyLedger-TrollStore** artifact when the build finishes.
4. Extract the artifact, open `DailyLedger-1.1.0.tipa` on the iPhone, and choose TrollStore.

No Apple Developer account is needed for TrollStore installation.

## Build locally with Xcode

1. Install XcodeGen: `brew install xcodegen`
2. From this folder, run `xcodegen generate`.
3. Open `DailyLedger.xcodeproj` in Xcode.

The deployment target and App Intents are set to iOS 16.0. The app is iPhone-only and optimized for portrait use.

## Shortcuts setup

Open Daily Ledger once after installation, then open the Shortcuts app and search for **Daily Ledger** under Apps. The Add Expense and Add Income actions accept:

- Amount (required)
- Category (optional; defaults to Other or Salary)
- Description (optional)
- Date (optional; defaults to now)

For a personal automation, add one of these actions and enable **Run Immediately** where iOS offers that option. Whether an automation can run while locked also depends on the trigger selected by Apple and whether the phone has been unlocked once since restarting.

## Supported import columns

CSV files must contain `type`, `amount`, and `date`. They may also contain `id`, `category`, and either `details` or `note`.

- `type`: `income` or `expense`
- `amount`: plain decimal value, such as `25.50`
- `date`: ISO 8601, such as `2026-07-19T08:30:00Z`

Imported records are merged using their UUID when an `id` is present.
