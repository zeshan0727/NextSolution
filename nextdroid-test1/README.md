# NextDroid Android 11 — Test 2

This test package targets iPhone 14 Pro Max on iOS 16.0 installed through
TrollStore. It uses UTM's JIT/QEMU runtime and creates a persistent Bliss OS
14.10.3 (Android 11) VM with OpenGApps.

The TIPA is intentionally small. On first launch it downloads the official
2,087,714,816-byte Bliss OS image, validates SHA-256, creates a 16 GiB sparse
data disk, and writes the UTM configuration into the app's Documents folder.

Expected Android image SHA-256:

`9feb9482e6e5c41c52172a0d42a436ea808de1cfdd6b1e0187dc883b2df9085c`

## First test flow

1. Remove Test 1 and install `NextDroid_Android11_Test2.tipa` with TrollStore.
2. Open NextDroid and accept the one-time Android download.
3. Keep NextDroid open until verification completes.
4. Close and reopen NextDroid.
5. Tap `NextDroid Android 11` and confirm that the Bliss OS boot menu appears.

This is a boot and compatibility test. The VM currently boots the Android 11
installer/live environment; automatic installation and direct one-tap Android
launch are planned after the device boot result is confirmed.
