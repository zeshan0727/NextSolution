# Next Ledger — App Store Release Checklist

## App Store Connect
- [x] App record created: Next Ledger
- [x] Bundle ID: `com.nextsolution.nextledger`
- [x] Version: 1.0
- [x] App Privacy published
- [x] Age rating completed
- [x] Description / keywords / URLs prepared
- [x] Privacy policy published
- [x] Support page published
- [ ] DSA trader status completed if distributing in EU
- [ ] Price verified as Free
- [ ] Apple Silicon Mac availability disabled for v1.0
- [ ] Apple Vision Pro availability disabled for v1.0 if shown
- [ ] App Review contact information entered
- [ ] App Review notes entered
- [ ] Build 1 selected
- [ ] Screenshots uploaded

## App Store source audit
- [x] Dedicated App Store release branch isolated
- [x] AI tab removed
- [x] OpenAI service removed from App Store branch
- [x] DeepSeek service removed from App Store branch
- [x] AI chat views removed from App Store branch
- [x] SMS importer UI and service sources removed from App Store branch
- [x] SMS preference methods removed from `LedgerStore`
- [x] SMS preference fields and bank-message parsing removed from App Store models
- [x] No SMS / Messages entitlement requested
- [x] Personal `Amara` transfer-report special case removed
- [x] Personal device marker `Z-iP-14PM-16.0` removed from categorization logic
- [x] Personal account UUID/chart migration table removed from App Store models
- [x] Personal legacy CSV account-name mappings removed
- [x] Brand-specific default vendor rules reduced to generic terms
- [x] Current CSV format uses generic account import and preserves source/destination currencies
- [x] Developer Lab removed
- [x] Local legacy chat-search helper removed
- [x] Unused secret-store helper removed
- [x] Legacy `dailyledger://` URL scheme removed; only `nextledger://` remains
- [x] Customer-facing "Books vs Message Balance" renamed to "Balance Reconciliation"
- [x] Backup UI uses generic Files wording rather than implying a direct third-party integration
- [x] Customer-facing "iOS 26 Glass Style" renamed to "Glass Style"
- [x] App Intents that write financial records require local device authentication
- [x] Privacy manifest present
- [x] UserDefaults required-reason declaration present
- [x] Non-exempt encryption key set to NO
- [x] iCloud Documents entitlement configured
- [x] App-specific privacy/support web pages contain no analytics or ad scripts
- [x] App Review notes contain only shipped App Store functionality
- [x] Rejection-risk source marker guard added: `AppStore/verify_appstore_source.sh`
- [ ] Run source guard on Mac against exact checkout
- [ ] Build exact generated Xcode target and resolve any compiler warnings/errors
- [ ] Verify no private frameworks or unsupported entitlements in archived binary

## Functional test before upload
- [ ] Clean launch on current iOS simulator/device
- [ ] Launch on iOS 16-compatible test device/build if available
- [ ] Create/edit/delete account
- [ ] Create/edit/delete income
- [ ] Create/edit/delete expense
- [ ] Transfer between accounts
- [ ] Running balance correctness
- [ ] Reports open without crash
- [ ] Budget creation and alert behavior
- [ ] Local notifications permission path
- [ ] CSV export
- [ ] JSON export
- [ ] CSV import
- [ ] JSON restore/import
- [ ] iCloud backup
- [ ] iCloud restore
- [ ] Shortcuts actions with device authentication
- [ ] Light mode
- [ ] Dark mode
- [ ] Offline use
- [ ] No debug/developer controls exposed

## Screenshot preparation
- [x] Sanitized screenshot demo data created
- [x] Screenshot shot list created
- [ ] Import screenshot demo data into clean simulator build
- [ ] Capture Home
- [ ] Capture Accounts
- [ ] Capture Transactions
- [ ] Capture Reports
- [ ] Capture Budgets
- [ ] Capture Backup & Export
- [ ] Capture Dark Mode
- [ ] Add consistent marketing captions
- [ ] Export accepted App Store dimensions with no alpha

## Xcode / Xcode Cloud
- [ ] Sign into Xcode with developer account
- [ ] Select developer Team
- [ ] Automatic signing enabled
- [ ] Bundle ID verified
- [ ] iCloud capability/container verified
- [ ] Shared scheme verified
- [ ] Archive action enabled
- [ ] First local Release build succeeds
- [ ] Inspect generated target membership
- [ ] Configure Xcode Cloud workflow
- [ ] Xcode Cloud archive succeeds
- [ ] Build appears in TestFlight/App Store Connect
- [ ] TestFlight smoke test completed

## Final submission
- [ ] App Review contact name/email/phone entered
- [ ] Sign-in required = No
- [ ] Review notes pasted from `APP_REVIEW_NOTES.md`
- [ ] Export compliance shows no additional documentation required
- [ ] Content rights correct
- [ ] Privacy answers rechecked against exact uploaded binary
- [ ] Screenshots match exact shipped functionality
- [ ] Add for Review
- [ ] Submit for Review
