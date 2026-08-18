# Next Ledger — App Store Readiness

Target release: **1.0.0 (1)**

## Distribution identity

- Product name: Next Ledger
- Bundle ID: `com.nextsolution.nextledger`
- Minimum iOS: 16.0
- App Store build condition: `APPSTORE`
- Signing: Automatic
- iCloud container: `iCloud.com.nextsolution.nextledger`
- Background refresh identifier: `com.nextsolution.nextledger.backup-refresh`

## Already prepared

- Dedicated App Store release branch.
- App Store version/build reset to 1.0.0 (1).
- Dedicated bundle identifier.
- Privacy manifest baseline added.
- iCloud Documents entitlements added.
- App/URL/background identifiers aligned to Next Ledger.
- 1024×1024 App Store icon asset is present.
- RootHide daemon/package directories are outside the iOS application target.

## Must finish before archive

- Hide the Bank SMS / RootHide importer UI and actions in `APPSTORE` builds.
- Keep the SMS automation only in the jailbreak/TrollStore distribution.
- Remove device-specific text such as `Z-iP-14PM-16.0` from customer-facing UI.
- Make the About version read from the app bundle instead of a hard-coded old version.
- Add an in-app Privacy Policy link.
- Publish an app-specific Next Ledger privacy policy.
- Audit OpenAI/DeepSeek disclosures and add explicit user-facing notice before any ledger context is sent off-device.
- Verify selectable AI model identifiers against the production APIs before release.
- Run a Release/Archive build with current Xcode and resolve all signing, entitlement, privacy-manifest and API warnings.
- Test clean install, upgrade/import, iCloud backup/restore, CSV/JSON import/export, Shortcuts, notifications, AI-disabled mode and offline behavior.

## Apple Developer portal

Create an explicit App ID for `com.nextsolution.nextledger`. Enable iCloud and Background Modes as required by the target. Create/select the iCloud container `iCloud.com.nextsolution.nextledger` for iCloud Documents.

## App Store Connect

Create a new iOS app record named **Next Ledger** using bundle ID `com.nextsolution.nextledger`. Complete app privacy, privacy policy URL, age rating, category, support URL, screenshots, description, keywords, review notes and export-compliance questions before submission.
