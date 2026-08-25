# Next Multi Browser

iPhone-first test build for 1–20 simultaneously loaded WKWebView browser panes. Includes grid/focus mode, per-pane navigation, load-all URL, reload-all, 20 isolated persistent browser profiles, and adaptive iPhone/iPad layouts.

Current test build: 1.1.8.

### iPad Pro 12.9 layout

- Native universal iPhone/iPad build with all four iPad orientations enabled.
- 12.9-inch iPad Pro portrait uses three browser columns; landscape uses four.
- Larger address bars and browser controls on iPad.
- Live rotation rebuilding and responsive two-column iPad Split View support.
- Release packaging includes both `.tipa` and identical `.ipa` install files.

- The `Profiles` tab lists all 20 browser containers with last-used time, storage size, session status, and environment summary.
- Every browser has a separate persistent website data store and process pool so Google cookies and other login state are never shared between panes.
- iOS 17+ uses WebKit named persistent data stores. The sideloaded iOS 15/16 build assigns a separate on-disk WebKit directory to each profile, including cookies, local storage, IndexedDB, cache storage, and service-worker data.
- Cookie archives created by 1.0.5 are migrated into the new persistent profile the first time it opens.
- Each profile can be renamed, opened directly at Google Sign-In, reopened at its last page, or cleared without affecting the other 19 profiles.
- Each profile now has independent icon/color, device and viewport, user-agent preset, language/locale, region, timezone, and saved website-permission choices.
- Environment Manager includes one profile-scoped randomize button that selects a matching device, user agent, language, region, and timezone without touching cookies or website data.
- The Profiles tab includes one global action that assigns 20 unique phone-based environment combinations while keeping every profile's persistent storage identifier and login data unchanged.
- Manual device selection includes multiple iPhones, Google Pixel 9 Pro/XL, Samsung Galaxy S25/Ultra, OnePlus 13, Xiaomi 15 Ultra, macOS Safari desktop, and Windows Chrome desktop. Choosing a device pairs its compatible user agent and returns language, region, and timezone to Automatic.
- Individual and global environment randomization remain phone-only, so automated 20-browser assignments never select a desktop preset.
- Environment choices include 17 languages, 24 regions, and 27 timezone choices.
- Profile actions include settings-only duplication into a fresh independent container, clear, delete/reset, internal backup/restore, and a developer diagnostics panel.
- Storage management reports cookies, cache, local storage, IndexedDB, other website data, total size, and the persistent storage location.
- Automated simulator tests create 20 unique stores, validate cookie isolation and relaunch persistence, and confirm deleting one profile does not affect another.

- A dedicated Imported URL Queue accepts any number of pasted links, removes duplicate lines, saves progress, and explicitly loads the next non-repeating batch of up to 20 links into randomly selected browser panes.
- The previous Random 4 URLs action has been removed. Home All, Reload All, and Load Same URL now live in one compact Actions menu; browser quantity, auto refresh, and VPN share a separate Controls menu.
- A dedicated blue, cyan, and violet multi-window app icon is included for iPhone and iPad.
- Global auto refresh: Off / 1m / 2m / 3m / 5m / 10m, applied to current and newly created browsers.
- Per-browser refresh override remains available.
- Free multi-country VPN browser using VPN Gate OpenVPN relay profiles.
- VPN list loading races the primary feed, saved mirrors, and bootstrap mirrors, then falls back to the cached last-good list.
- Inline media policy is installed at document start in every frame so video remains inside its browser pane instead of opening the native player.
- Best-effort automatic media playback begins without a manual play tap, with muted retry when unmuted autoplay is blocked by WebKit or site policy.
- Apple Password AutoFill support annotates username/email, current-password, new-password, and one-time-code fields at document start and as dynamic login forms appear. This lets iOS show its Passwords/iCloud Keychain controls when they are enabled on the device, without reading or sharing typed credentials between browser profiles.
- Auto-focused first-step email fields receive a one-time, value-preserving focus refresh so WebKit recalculates their AutoFill keyboard traits. Login emails stay classified as usernames, while recovery/contact email fields receive the separate email AutoFill hint.
