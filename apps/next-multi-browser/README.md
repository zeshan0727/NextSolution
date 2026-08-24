# Next Multi Browser

iPhone-first test build for 1–20 simultaneously loaded WKWebView browser panes. Includes grid/focus mode, per-pane navigation, load-all URL, reload-all, 20 isolated persistent browser profiles, and adaptive iPhone/iPad layouts.

Current test build: 1.0.5.

- New `20 Profiles` tab lists and manages every browser profile.
- Every browser has a separate website data store and process pool so Google cookies are never shared between panes.
- iOS 17+ uses WebKit named persistent data stores. iOS 15/16 restores a protected per-profile cookie archive into an isolated WebKit store when the app launches.
- Each profile can be renamed, opened directly at Google Sign-In, reopened at its last page, or cleared without affecting the other 19 profiles.

- Global auto refresh: Off / 1m / 2m / 3m / 5m / 10m, applied to current and newly created browsers.
- Per-browser refresh override remains available.
- Free multi-country VPN browser using VPN Gate OpenVPN relay profiles.
- VPN list loading races the primary feed, saved mirrors, and bootstrap mirrors, then falls back to the cached last-good list.
- Best-effort automatic media playback after navigation, with muted retry when unmuted autoplay is blocked by WebKit/site policy.
