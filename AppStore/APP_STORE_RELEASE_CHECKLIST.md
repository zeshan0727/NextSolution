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
- [x] SMS importer settings removed from customer UI
- [x] No SMS / Messages entitlement requested
- [x] Developer Lab removed from App Store branch
- [x] Local legacy chat-search helper removed from App Store branch
- [x] Unused secret helper excluded from App Store target
- [x] Personal legacy CSV account-name mappings removed
- [x] Current CSV format uses generic account import and preserves source/destination currencies
- [x] Legacy `dailyledger://` URL scheme removed; only `nextledger://` remains
- [x] Customer-facing "Books vs Message Balance" renamed to "Balance Reconciliation"
- [x] Misleading Google Drive labels remapped to generic Files wording
- [x] Customer-facing "iOS 26 Glass Style" renamed to "Glass Style"
- [x] App Intents that write financial records require local device authentication
- [x] Privacy manifest present
- [x] UserDefaults required-reason declaration present
- [x] Non-exempt encryption key set to NO
- [x] iCloud Documents entitlement configured
- [x] App-specific privacy/support web pages contain no analytics or ad scripts
- [x] App Review notes contain only shipped App Store functionality
- [ ] Remove/neutralize remaining personal-specific report rule in `LedgerStore` (`Amara` transfer special-case)
- [ ] Review dormant legacy SMS preference methods/model fields and remove if they can be safely migrated without breaking existing backup compatibility
- [ ] Run final source scan on exact release branch for OpenAI, DeepSeek, SMS, Messages, RootHide, jailbreak, TrollStore, Sileo, daemon, private framework/API references
- [ ] Verify exact generated Xcode target does not compile excluded/internal files
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
