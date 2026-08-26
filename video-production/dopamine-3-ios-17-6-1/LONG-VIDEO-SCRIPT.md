# Dopamine 3 on iOS 17.6.1 — long video script

Target runtime: 6–7 minutes  
Format: 16:9 long-form tutorial  
Test device visual: real Next Jailbreak iPad Home Screen with Dopamine and Sileo
Article: https://nextjailbreak.com/dopamine-3-jailbreak-ios-17-6-1.html

## Accuracy lock before editing

- Say **A12-family and A13**, not “all A12+ devices.”
- On iOS/iPadOS 17.6.1, official support includes A12, A12X, A12Z and A13.
- A14–A17 and M1–M2 are officially listed only through iOS/iPadOS 17.3.1 on real devices.
- Latest release verified during preparation: Dopamine 3.0.5 on 13 August 2026.
- Use only the official Dopamine download page and GitHub release page.

## Scene 1 — Hook and proof (0:00–0:25)

**Visual**

- Open with the finished thumbnail animation.
- Cut to the real iPad Home Screen.
- Slow zoom toward the Dopamine and Sileo icons.
- Add a small label: “REAL iPAD RESULT”.

**Narration**

> Dopamine 3 can jailbreak iOS and iPadOS 17.6.1 on supported A12-family and A13 devices. This is my real iPad result: Dopamine is installed, Sileo is working, and in this video I will show the complete process from the official download to the final jailbreak. But first, there is one important compatibility detail that can save you from trying this on the wrong device.

## Scene 2 — Correct compatibility (0:25–1:10)

**Visual**

- Show a clean chip matrix.
- Green: A12, A12X, A12Z, A13.
- Red: A14–A17, M1–M2 on 17.6.1.
- Display “Source checked: official Dopamine support matrix”.

**Narration**

> Do not treat this as support for every A12-or-newer device. On iOS 17.6.1, the supported modern range is the A12 family and A13. That includes A12, A12X and A12Z iPads, plus A13 devices. Newer A14 through A17 devices, and M1 or M2 iPads, are not supported on 17.6.1. Their official real-device limit is iOS 17.3.1. So before downloading anything, confirm both your exact software version and your chip.

## Scene 3 — Verify the test device (1:10–1:35)

**Visual**

- Record Settings → General → About.
- Keep “Software Version 17.6.1” and “Model Name” readable.
- Return to the Home Screen and show Dopamine and Sileo.

**Narration**

> Open Settings, General, and About. Confirm that the software version is exactly 17.6.1, then identify your device model. I recommend recording this screen clearly because it proves the firmware separately from the jailbreak result shown on the Home Screen.

## Scene 4 — Preparation and official files (1:35–2:10)

**Visual**

- Backup icon, battery above 50 percent, cable, computer.
- Show the official URLs on screen:
  - ellekit.space/dopamine
  - github.com/opa334/Dopamine/releases
  - ios.cfw.guide/installing-dopamine

**Narration**

> Make a current Finder or iTunes backup, charge the device, and use a reliable cable. Download Dopamine only from the official developer page or the verified GitHub releases. Do not use a mirrored IPA or a shortened download link. The official installation guide currently uses PlumeImpactor to sign and install the app on firmware like 17.6.1.

## Scene 5 — Install Dopamine (2:10–3:00)

**Visual**

- Connect and trust the iPad.
- In PlumeImpactor: Settings → Sign In.
- Drag the official Dopamine IPA into the window.
- Select Install.
- Never show the Apple Account password in the recording.

**Narration**

> Connect the iPad to the computer and accept the Trust prompt. Open PlumeImpactor, go to Settings and Sign In, then sign in with your Apple Account. Keep all credentials hidden from the recording. Drag the official Dopamine IPA into PlumeImpactor and choose Install. Wait until the Dopamine icon appears on the Home Screen before disconnecting the device.

## Scene 6 — Trust and Developer Mode (3:00–3:35)

**Visual**

- Settings → General → Device Management.
- Trust the signed developer profile.
- Settings → Privacy & Security → Developer Mode.
- Complete the restart.

**Narration**

> Next, open Settings, General, and Device Management. Select the Apple Account used for signing and trust the application. Then open Privacy and Security, enable Developer Mode, and complete the restart requested by iPadOS. Without Developer Mode, the sideloaded jailbreak app will not run correctly.

## Scene 7 — Run the jailbreak (3:35–4:25)

**Visual**

- Fresh reboot.
- Open Dopamine immediately.
- Show the installed Dopamine version.
- Tap Jailbreak.
- Keep the camera rolling if the screen turns off and back on.

**Narration**

> A fresh reboot is recommended before the first attempt. As soon as the iPad starts, open Dopamine and tap Jailbreak. On A12-family and A13 devices running iOS or iPadOS 16.6 and later, the screen may briefly turn off and back on during the exploit. The official guide describes this as normal. If the app closes or the device reboots without completing, reboot normally, open Dopamine again, and retry.

## Scene 8 — Sileo and required packages (4:25–5:15)

**Visual**

- Show Sileo appearing on the Home Screen.
- Open Sources → ElleKit → All Categories → ElleKit.
- Queue ElleKit.
- Search PreferenceLoader and queue it.
- Confirm and tap Reboot Device.

**Narration**

> After a successful jailbreak, Sileo should appear on the Home Screen. Open Sileo, go to Sources, open the ElleKit repository, and queue ElleKit. Then search for PreferenceLoader and add it to the same queue. Confirm the installation and tap Reboot Device when it finishes. This is a userspace reboot, so the device should remain in the jailbroken state.

## Scene 9 — Verify the result (5:15–5:45)

**Visual**

- Refresh Sileo sources.
- Open one package page without installing it.
- Return to the Home Screen.
- Reuse the real proof frame with Dopamine and Sileo.

**Narration**

> Reopen Sileo, refresh the sources, and confirm that package pages load normally. At this stage the jailbreak is active. Install only rootless packages that explicitly support your iOS version and architecture, and add tweaks one at a time so any problem is easy to identify.

## Scene 10 — Reboot behavior and seven-day signing (5:45–6:20)

**Visual**

- Simple flow: Full reboot → non-jailbroken state → open Dopamine → Jailbreak.
- Add “Re-sign before 7 days” beside the Dopamine app icon.

**Narration**

> Dopamine is semi-untethered. After a full reboot, the device starts normally without the jailbreak active. Open Dopamine and tap Jailbreak again to restore it. On 17.6.1, a free Apple Account sideload normally needs to be re-signed every seven days, so refresh the app before the signature expires.

## Scene 11 — Safety and outro (6:20–6:50)

**Visual**

- Show backup, official sources and rootless compatibility icons.
- End card: article URL, channel handle and Subscribe button.

**Narration**

> Keep a backup, avoid random repositories, and never update iOS until you have checked the jailbreak status for your exact device. The full written guide, compatibility table, official links and troubleshooting steps are available on Next Jailbreak. If this walkthrough helped, subscribe for more real-device jailbreak guides and verified tweak coverage.

## Editor checklist

- Blur Apple Account email, device serial number, UDID, Wi-Fi details and notifications.
- Show Settings → About before claiming the 17.6.1 test.
- Keep Dopamine and Sileo icons large enough to read on a phone.
- Do not label A14 or newer devices as supported on 17.6.1.
- Use the corrected thumbnail text: “A12–A13 DEVICES”.
- Add the AI-narration disclosure in the description, not as an intrusive on-screen badge.
