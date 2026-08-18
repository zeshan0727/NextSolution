# Next Signer — Reliable IPA Signing Guide

This document defines the signing rules for Next Signer so future builds do not reject valid signed apps with extra home-grown signature checks.

## Supported flow

1. Import a P12 signing identity, its password, and a matching `.mobileprovision` profile.
2. Choose an IPA/TIPA locally on the iPhone.
3. Preflight the credentials and requested bundle identifier before extracting/signing.
4. Extract `Payload/*.app` locally.
5. Rewrite the requested main bundle identifier/name and ordinary nested app/extension identifiers.
6. Call Zsign on the extracted `.app` folder with the P12 + provisioning profile.
7. Treat Zsign's Boolean result as the signing-engine result.
8. After Zsign succeeds, validate only deterministic package state: final Info.plist, embedded provisioning profile, and successful IPA packaging.
9. Export the signed IPA locally.
10. Only after successful local signing may the user publish the already-signed IPA.

The unsigned source IPA is never uploaded.

## Why unsigned apps are supported

Upstream zsign is designed to re-sign IPA/app/Mach-O files. When a Mach-O has no existing code-signature load command/space, zsign's signing engine reallocates code-signature space and retries signing. Therefore Next Signer must not require the source app to already contain `_CodeSignature`, `CodeResources`, or a pre-existing `LC_CODE_SIGNATURE` command.

## Credential preflight

Before signing:

- Open the P12 with Apple's Security framework (`SecPKCS12Import`). A failure means the P12/password is invalid.
- Extract the certificate from the P12.
- Decode the plist embedded in the mobileprovision.
- Reject an expired provisioning profile.
- Require the P12 certificate to appear in the profile's `DeveloperCertificates` list.
- Read the profile's `application-identifier` entitlement and confirm the requested bundle identifier is covered by its exact or wildcard App ID.
- For nested apps/extensions, confirm each rewritten identifier is also covered by the profile.

These checks identify real configuration errors before the signing engine runs.

## Post-sign validation rules

Do **not** hard-fail a successful Zsign operation because of any of the following secondary checks:

- `Zsign.checkSigned()`
- presence/absence of `_CodeSignature/CodeResources`
- a custom parser searching for `LC_CODE_SIGNATURE`

Those checks have already produced false negatives on valid third-party IPA layouts.

After Zsign returns success, Next Signer may hard-check only:

- final `Info.plist` is readable;
- final `CFBundleIdentifier` equals the requested identifier;
- `embedded.mobileprovision` exists and remains decodable;
- the output IPA is successfully written and is a ZIP archive.

## Extensions and special capabilities

A single wildcard provisioning profile can cover ordinary bundle identifiers under its wildcard namespace. Some apps/extensions use capabilities that require explicit App IDs/profiles, such as App Groups, iCloud, Push Notifications, Sign in with Apple, Network Extensions, or other restricted entitlements. Such apps may require per-extension provisioning profiles and cannot always be made valid by changing bundle identifiers alone.

If a nested bundle identifier is not covered by the imported profile, Next Signer must stop before signing and show the exact identifier/profile mismatch instead of creating an IPA that iOS will later reject.

## Distribution

Signing and publishing are separate operations. GitHub credentials are not required to sign. For publishing, upload only the already-signed IPA as a GitHub Release asset, then update the OTA manifest/catalog. Never upload the unsigned source IPA.

## CI verification

Next Signer 1.2.1 must be built with the patched local Zsign package so `embedded.mobileprovision` is preserved during signing before a test TIPA is distributed.

## Reference

Upstream zsign documents P12 + mobileprovision signing, bundle-ID/name changes, app-bundle signing, and re-signing of IPA/Mach-O content. Next Signer's implementation should follow zsign's own success/failure result rather than duplicating its Mach-O signature parser.
