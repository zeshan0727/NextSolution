# Next Log

Next Log is the shared diagnostic app for Next Solution jailbreak tweaks.

## Diagnostic protocol

- Control file: `/var/mobile/Library/Preferences/com.nextsolution.nextlog.plist`
- Darwin notification: `com.nextsolution.nextlog/control.changed`
- Shared logs: `/var/mobile/Library/Logs/NextSolution/<tweak>.log`
- Reports: `/var/mobile/Library/Logs/NextSolution/Reports/`

A diagnostic-compatible tweak should listen for the Darwin notification, inspect `enabled` and `activeTweak`, and write detailed timestamped lines only when its own tweak ID is active.

Module Glass 1.0.5 is the first runtime using this protocol. Other tweaks can adopt the same protocol without changing the Next Log app.
