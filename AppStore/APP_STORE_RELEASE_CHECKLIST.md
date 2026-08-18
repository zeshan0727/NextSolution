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
- [x] App Store release branch isolated
- [x] AI tab removed
- [x] OpenAI service removed
- [x] DeepSeek service removed
- [x] AI chat views removed
- [x] SMS importer settings removed from customer UI
- [x] No SMS or Messages entitlement/API requested
- [x] Privacy manifest present
- [x] Non-exempt encryption key set to NO
- [x] iCloud container entitlement configured
- [ ] Remove or exclude unused Developer Lab source from shipping target
- [ ] Remove or exclude unused local LedgerChatSearch source from shipping target
- [ ] Rename/remove any remaining customer-facing "Message" terminology such as "Books vs Message Balance"
- [ ] Search source for OpenAI, DeepSeek, SMS, Messages, RootHide, jailbreak, TrollStore, Sileo, daemon, private API references and confirm none ship in target
- [ ] Verify no private frameworks or unsupported entitlements

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
- [ ] Shortcuts actions
- [ ] Light mode
- [ ] Dark mode
- [ ] Offline use
- [ ] No debug/developer controls exposed

## Screenshot preparation
- [x] Sanitized screenshot demo data created
- [x] Screenshot shot list created
- [ ] Import screenshot demo data into clean build
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
