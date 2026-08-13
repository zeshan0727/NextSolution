# PhoneAura 0.5.1 Diagnostic Recovery Build

This build intentionally restores the untouched PhoneAura 0.4.16 runtime and does **not** load the 0.5.0 `PhoneAuraNativeFeatures` contact-book hook.

It adds two diagnostic components only:

- `PhoneAuraDiagnostics.dylib`: passive MobilePhone diagnostics. It does not replace PhoneAura controller methods.
- `PhoneAuraConsole.app`: a separate console for runtime status, feature tests, live logs, crash import, copy/share, and clearing logs.

## Console fields

- Running / heartbeat
- Diagnostic version
- MobilePhone process and PID
- Rootless vs RootHide/Rootful environment
- Base PhoneAura runtime loaded state
- Whether the old 0.5.0 feature hook is still loaded
- Current visible Phone controller
- Last diagnostic command

## Feature tests

- Favorites
- Recents
- Contacts + account/container permission state
- Keypad
- Voicemail/system tab
- Full diagnosis
- Current UI/controller snapshot
- Import latest MobilePhone crash report

Logs are stored at `/var/mobile/Library/Logs/PhoneAura/PhoneAuraDiagnostics.log` and can be shared from the console.
