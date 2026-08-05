# PhoneAura 0.5.0 Native Features Companion

This source builds a small companion dylib that runs beside the published PhoneAura 0.4.16 runtime. The original PhoneAura dylib, Studio app, preferences bundle, visual design, tab replacements and package identifier remain in place.

## Added

- Native-style **Contact Books** selector inside the existing PhoneAura Contacts header.
- All Contacts, individual contact accounts/containers, and contact groups/lists.
- Saved selection across Phone app launches.
- Refresh after Contacts database changes.
- RootHide and standard rootless packages.

## Native feature compatibility

PhoneAura continues to delegate cellular calls, incoming calls, active-call controls, conference calls, Visual/Live Voicemail, Caller ID, spam handling, blocked callers, emergency calling, Dual SIM, Wi-Fi Calling, Bluetooth, CarPlay, Siri and Handoff to Apple's original controllers. Availability depends on iOS, device, language, region and carrier.

Features introduced only in later iOS versions—such as Apple's call recording/transcription, Apple Intelligence summaries, Live Translation, Contact Posters and third-party default calling apps—cannot be added as genuine native iOS 16 services by a tweak. PhoneAura does not simulate or falsely label those services.
