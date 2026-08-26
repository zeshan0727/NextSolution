# Next Signer

Next Signer is a small iOS utility for the Next Jailbreak private app catalog.

## Goal

After one-time setup, publishing an app is:

1. Open Next Signer.
2. Choose an IPA from Files.
3. Confirm the app name and a `com.nextsolution.*` bundle identifier.
4. Tap **Sign & Publish**.
5. The GitHub workflow signs the IPA, publishes the signed build, creates the OTA manifest, and updates `https://nextjailbreak.com/install/` automatically.

No IPA needs to be sent through ChatGPT and no third-party signing app is required.

## Storage architecture

Next Signer deliberately separates the catalog from large binaries:

- GitHub repository: source, website, icons, OTA manifests, and `install/apps.json`.
- GitHub draft release `nextsigner-inbox`: temporary unsigned IPA staging from the iPhone to the signing workflow. Release assets avoid the normal repository/browser file-size limit.
- Cloudflare R2 bucket `next-signer-apps`: preferred storage for signed IPA files.
- Public R2 hostname: `https://files.nextjailbreak.com`.
- GitHub Releases: automatic fallback if the R2 Actions secrets are not configured.

New R2-published builds use immutable versioned object keys such as:

`apps/ipa/<bundle-slug>/<version>/<bundle-slug>-<version>-<build>.ipa`

The workflow verifies the published URL before updating the OTA manifest. It also records the SHA-256 digest, byte size, download URL, and storage backend in the catalog entry.

## Security model

Next Signer does **not** keep the Apple Distribution P12, P12 password, provisioning profile, or Cloudflare R2 secret key on the iPhone. Apple signing material and R2 credentials are stored as encrypted GitHub Actions secrets. The iPhone stores only a repository-scoped GitHub token in the iOS Keychain.

Required signing Actions secrets on `zeshan0727/NextSolution`:

- `NEXTSIGNER_P12_BASE64`
- `NEXTSIGNER_P12_PASSWORD`
- `NEXTSIGNER_MOBILEPROVISION_BASE64`

Required R2 Actions secrets for direct Cloudflare publishing:

- `CLOUDFLARE_R2_ACCESS_KEY_ID`
- `CLOUDFLARE_R2_SECRET_ACCESS_KEY`

The R2 Account ID and S3 endpoint are configured directly in the workflow for this Cloudflare account. The R2 credentials should be scoped only to the `next-signer-apps` bucket with object read/write permission. Do not commit or paste those credentials into app source, website JavaScript, catalog JSON, manifests, issues, or logs.

Create the Apple signing base64 values locally. On macOS:

```bash
base64 -i Distribution.p12 | pbcopy
base64 -i NS_3.mobileprovision | pbcopy
```

On Windows PowerShell:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("Distribution.p12")) | Set-Clipboard
[Convert]::ToBase64String([IO.File]::ReadAllBytes("NS_3.mobileprovision")) | Set-Clipboard
```

Never commit the P12, its password, the raw provisioning profile, or R2 credentials to the repository.

## GitHub token for the app

Create a fine-grained personal access token scoped only to `zeshan0727/NextSolution` with:

- Contents: Read and write
- Actions: Read and write

Enter the token once under Next Signer → Settings. It is stored in Keychain with `ThisDeviceOnly` accessibility.

## Signing engine

The backend workflow uses the MIT-licensed `zhlynn/zsign` project pinned to commit:

`e803f870dc686e6161d00d9b22c425b8acdfacee`

The workflow:

- receives an IPA in the draft GitHub release inbox;
- signs it with the configured P12 and Ad Hoc provisioning profile;
- rewrites the requested main bundle identifier and app name;
- calculates SHA-256 and file size;
- publishes the signed IPA to Cloudflare R2 when R2 secrets are configured;
- falls back to the `private-apps` GitHub Release if R2 is not configured;
- verifies the public download URL;
- creates the OTA manifest;
- updates `install/apps.json`;
- removes the unsigned staging asset after a successful publish.

## R2 public download layout

Production signed IPA downloads use:

`https://files.nextjailbreak.com/apps/ipa/<bundle-slug>/<version>/<filename>.ipa`

Keep manually uploaded test packages separated by type when practical, for example:

- `apps/ipa/`
- `apps/tipa/`
- `apps/deb/`

The R2 custom domain is public. Do not upload private certificates, provisioning profiles, API tokens, passwords, or other secrets to the public bucket.

## Existing app migration

The repository includes `.github/workflows/migrate-private-apps-to-r2.yml`. After the two R2 repository secrets are configured, run that workflow manually and enter `MIGRATE`. It copies existing GitHub-hosted IPA binaries into R2, verifies each public R2 URL, rewrites the OTA manifests and catalog entries, and intentionally leaves the original GitHub Release assets in place as rollback copies.

## Important compatibility note

A wildcard Ad Hoc profile is suitable only when the app's required entitlements are compatible with that profile. Apps using capabilities such as iCloud, Push Notifications, App Groups, Associated Domains, Network Extensions, or extension-specific entitlements may require explicit App IDs and additional provisioning profiles. Next Signer should fail rather than silently remove those capabilities.

## TIPA build

`build-nextsigner-tipa.yml` builds the app without an Apple code signature and packages both `.ipa` and `.tipa` artifacts for TrollStore testing.
