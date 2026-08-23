# Module Glass 1.1.18 Release Source

RootHide and standard rootless packages for iOS 16+.

## 1.1.18

- Preserves the validated 1.1.17 Module Glass controls and External Host Isolation renderer.
- Places the Activation section after every existing control, matching NextLock's working layout.
- Includes functional Status, Device ID, Copy, Buy / Activate, and Check Activation actions.
- Uses the live Module Glass license registry and a $1.00 lifetime, one-device activation.
- Builds RootHide and rootless independently from the same source instead of renaming a package.
- Keeps activation state across upgrades and migrates the earlier 1.1.18 activation keys.

Run `python3 prepare_release.py <project-directory> <iphoneos-arm64|iphoneos-arm64e>` before packaging. The release workflow performs this step automatically and validates both DEBs.
