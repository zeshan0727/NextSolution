# Clean Home Labels 1.0.0

Clean Home Labels is a focused SpringBoard visual tweak for iOS 15+ that hides icon names while leaving app icons and badges untouched. It targets the user's iOS 16.0 RootHide device first and also ships a standard rootless build.

## Native-feature verification
Apple's iOS 16 Home Screen options cover page organization, App Library placement, and the Home Screen Search control, but do not provide a global switch to hide icon names. Apple's later Home Screen customization added materially different icon presentation options on newer iOS releases; this package deliberately targets iOS 15/16 where a global label-hiding control is absent. Repository history was checked before implementation and no existing `com.nextsolution.cleanhomelabels` package or equivalent single-purpose published tweak exists in NextSolution.

## Runtime design
The tweak injects only into `com.apple.springboard` and hooks the long-established `SBIconView -setLabelHidden:` path. When enabled, an incoming visible-label request is converted to hidden; when disabled, the original Apple argument is passed through unchanged. This preserves stock cases where SpringBoard already wants a label hidden (for example, contexts that intentionally suppress one) and avoids guessing at layout ownership or attaching gesture recognizers to private views.

Because existing icon views may not all receive another `setLabelHidden:` call immediately after a preference change, the release pane includes a genuine `Apply & Respring` action. This is intentional rather than forcing a broad runtime view-tree mutation.

## Working references inspected
- Next Home Lock 1.0.5: SpringBoard-only process guard, `arm64 arm64e`, 0x4000 segment alignment, CFPreferences, Darwin notifications, PreferenceLoader layout, and conservative constructor behavior.
- Next Aura (`com.nextsolution.unlockvibrate`) package metadata and recent release references in the repository.
- PhoneAura repository/tutorial history for Next Solution naming and publication conventions.
- Internet Lost Haptic's latest successful dual-package build/index workflow as a packaging reference only; no haptic behavior is reused.

## Upstream / market comparison
A longstanding public SpringBoard pattern uses `SBIconView`'s `setLabelHidden:` selector to control icon-name visibility. Kage's historical public source and older public SpringBoard examples were reviewed only to confirm that selector family; no source code, assets, branding, or descriptions were copied. Havoc products such as Griddy and Tinge were reviewed for current iOS 15/16 Home Screen customization patterns; Clean Home Labels does not reproduce their paid feature sets.

No third-party source is vendored, so there is no inherited code licence obligation in this repository. References are documented for provenance only.

## Compatibility
- iOS 15.0+
- Primary device target: iPhone 14 Pro Max, iOS 16.0, RootHide
- RootHide package: `iphoneos-arm64e`
- Standard rootless package: `iphoneos-arm64`

## Settings
- Hide Icon Names (default: On)
- Apply & Respring

No diagnostics, process IDs, runtime selectors, test buttons, or developer-only rows are exposed in the release pane.

## Installation / uninstall
Install the build matching the jailbreak environment from the Next Solution Sileo repository. The package filters injection to SpringBoard. Uninstalling removes the tweak and PreferenceLoader bundle; after respring, SpringBoard returns to its normal label behavior.

## Deterministic checks
`tests/test_runtime.py` verifies both enabled outcomes and both disabled/pass-through outcomes, SpringBoard-only targeting, expected selector presence, CFPreferences/Darwin wiring, package identity, settings controls, and absence of retired-repository links.

## Device test checklist
1. Install the RootHide build and respring.
2. Confirm app names are hidden while icons and badges remain visible.
3. Open folders and App Library and record whether their icon-label presentation is acceptable; the hook applies to `SBIconView` throughout SpringBoard.
4. Open Settings > Clean Home Labels; confirm only the two real controls appear.
5. Turn Hide Icon Names off, tap Apply & Respring, and confirm stock label behavior returns.
6. Turn it on again, Apply & Respring, and confirm labels hide again.
7. Confirm launching apps, rearranging icons, folders, widgets, and badges remain functional.

## Known limitation / runtime assumption
The `SBIconView -setLabelHidden:` selector is private. Build validation confirms the hook compiles and is packaged, but only a matching physical device can prove that iOS 16.0 SpringBoard invokes that selector for every intended icon context. The release must therefore be described as build-validated and awaiting device test until physical confirmation.
