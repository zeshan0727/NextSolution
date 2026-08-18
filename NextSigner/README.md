# Next Signer

Next Signer is a small iOS utility for the Next Solution private app catalog.

## Goal

After one-time setup, publishing an app is:

1. Open Next Signer.
2. Choose an IPA from Files.
3. Confirm the app name and a `com.nextsolution.*` bundle identifier.
4. Tap **Sign & Publish**.
5. The GitHub workflow signs the IPA and updates `https://nextsolution.cc/install/` automatically.

No IPA needs to be sent through ChatGPT and no third-party signing app is required.

## Security model

Next Signer does **not** keep the Apple Distribution P12, P12 password, or provisioning profile on the iPhone. Those are stored once as encrypted GitHub Actions secrets. The iPhone stores only a repository-scoped GitHub token in the iOS Keychain.

Required Actions secrets on `zeshan0727/NextSolution`:

- `NEXTSIGNER_P12_BASE64`
- `NEXTSIGNER_P12_PASSWORD`
- `NEXTSIGNER_MOBILEPROVISION_BASE64`

Create the base64 values locally. On macOS:

```bash
base64 -i Distribution.p12 | pbcopy
base64 -i NS_3.mobileprovision | pbcopy
```

On Windows PowerShell:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("Distribution.p12")) | Set-Clipboard
[Convert]::ToBase64String([IO.File]::ReadAllBytes("NS_3.mobileprovision")) | Set-Clipboard
```

Never commit the P12, its password, or the raw provisioning profile to the repository.

## GitHub token for the app

Create a fine-grained personal access token scoped only to `zeshan0727/NextSolution` with:

- Contents: Read and write
- Actions: Read and write

Enter the token once under Next Signer → Settings. It is stored in Keychain with `ThisDeviceOnly` accessibility.

## Signing engine

The backend workflow uses the MIT-licensed `zhlynn/zsign` project pinned to commit:

`e803f870dc686e6161d00d9b22c425b8acdfacee`

The workflow:

- receives an IPA in a draft release inbox;
- signs it with the configured P12 and Ad Hoc provisioning profile;
- rewrites the requested main bundle identifier and app name;
- publishes the signed IPA as a GitHub Release asset;
- creates the OTA manifest;
- updates `install/apps.json`;
- removes the unsigned staging asset after a successful publish.

## Important compatibility note

A wildcard Ad Hoc profile is suitable only when the app's required entitlements are compatible with that profile. Apps using capabilities such as iCloud, Push Notifications, App Groups, Associated Domains, Network Extensions, or extension-specific entitlements may require explicit App IDs and additional provisioning profiles. Next Signer should fail rather than silently remove those capabilities.

## TIPA build

`build-nextsigner-tipa.yml` builds the app without an Apple code signature and packages both `.ipa` and `.tipa` artifacts for TrollStore testing.
