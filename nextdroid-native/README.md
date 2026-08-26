# NextDroid Native

NextDroid Native compiles the UTM/QEMU iOS source together with a native
SwiftUI Android 11 setup experience. It does not inject a dynamic library or
patch an already-compiled application executable.

The TIPA contains the emulator engine but not the Android system image. On
first launch, it downloads and verifies the 2,087,714,816-byte Bliss OS
14.10.3 OpenGApps ISO, creates a persistent sparse data disk, registers the VM
with UTM, and exposes a direct **Start Android 11** action.

The Xcode archive is built without an Apple signing certificate or provisioning
profile. UTM's standard TrollStore/jailbreak packaging step embeds the runtime
entitlements needed for JIT execution.

The VM uses 2,048 MiB of guest RAM and a capped 256 MiB JIT translation cache.
Existing Test 4 configurations are migrated in place without replacing the
downloaded installer ISO or the persistent Android disk.
