# Next Multi Browser

iPhone-first test build for 1–20 simultaneously loaded WKWebView browser panes. Includes grid/focus mode, per-pane navigation, load-all URL, reload-all, persistent shared browsing data, and adaptive iPhone/iPad layouts.

Current test build: 1.0.4.

- Global auto refresh: Off / 1m / 2m / 3m / 5m / 10m, applied to current and newly created browsers.
- Per-browser refresh override remains available.
- Free multi-country VPN browser using VPN Gate OpenVPN relay profiles.
- VPN list loading races the primary feed, saved mirrors, and bootstrap mirrors, then falls back to the cached last-good list.
- Best-effort automatic media playback after navigation, with muted retry when unmuted autoplay is blocked by WebKit/site policy.
