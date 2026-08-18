# Next Ledger — App Store Screenshot Plan

Target: iPhone portrait, English (U.S.)

## Capture size

Preferred first set: **6.9-inch iPhone screenshots** using one of Apple's accepted portrait resolutions, ideally **1320 × 2868** or **1290 × 2796** from a current Pro Max simulator/device. If the final capture device produces a 6.5-inch accepted resolution, **1242 × 2688** or **1284 × 2778** is also accepted.

Use PNG or JPEG with no alpha channel. Keep screenshots as authentic captures of the shipped app UI. Marketing captions may be added around/above the real UI, but the UI itself should remain truthful.

## Demo data

Import `AppStore/ScreenshotDemoData.json` into a clean App Store build before capturing. It contains fictional accounts, vendors, balances and transactions only. Do not use personal bank/account data in App Store screenshots.

## Recommended 7-screen sequence

### 1 — Home
**Caption:** Your money at a glance

Capture the Home dashboard showing:
- Next Ledger header
- Spending shortcuts
- Balance card
- Income / Expenses
- Quick Add
- Recent transactions

This should be the strongest first screenshot because Apple may show the first screenshots in search results.

### 2 — Accounts
**Caption:** All your accounts, organized

Capture the Accounts tab with Everyday Account, Savings and Cash Wallet visible. Show balances and account grouping without exposing personal information.

### 3 — Transactions
**Caption:** Track every income and expense

Capture the Transactions tab with a clean mix of income, expenses and transfer records. Make sure vendor names are fictional and legible.

### 4 — Reports
**Caption:** Clear reports for better decisions

Capture Reports with the main report list and, if visually stronger, navigate into Financial Summary or Category Report and capture charts/totals.

### 5 — Budgets
**Caption:** Stay on top of your budgets

Open Settings → Budgets and capture Food & Dining, Transport and Shopping budget progress.

### 6 — Backup & Export
**Caption:** Back up and export your data

Capture Settings around Import & Export / Backup & Sync. Show CSV, JSON, iCloud backup and restore options. Do not show a file picker containing personal files.

### 7 — Dark Mode
**Caption:** Designed for light and dark mode

Use the Home or Reports screen in Dark Mode to demonstrate appearance support.

## Visual treatment

- Keep one consistent background treatment and typography across all screenshots.
- Avoid excessive marketing text; one short benefit statement per image.
- Do not claim bank syncing, SMS capture, AI, automatic bank import, payment processing, investing, lending or features not present in the App Store build.
- Do not show jailbreak, RootHide, TrollStore, Sileo, daemon, tweak or sideload references anywhere.
- Avoid fake notification banners, fake ratings, fake App Store badges or fabricated system UI.
- Keep the status bar clean and consistent.
- Use fictional data only.

## Capture checklist

- Clean install / screenshot demo data imported
- No personal account names, vendors or balances
- No SMS / AI / jailbreak UI anywhere
- Version 1.0 build
- Correct app icon installed
- Light mode captures first
- Dark mode capture last
- No debug overlays
- No Xcode debug banner
- No simulator window chrome in exported screenshots
- No transparency/alpha
