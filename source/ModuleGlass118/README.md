# Module Glass 1.1.19 Release Source

RootHide and standard rootless packages for iOS 16+.

## 1.1.19

- Introduces the first Next Jailbreak-branded Module Glass release.
- Adds a dark glass and electric-green hero header built with native UIKit.
- Organizes every supported Control Center module into five native Settings categories:
  - Core Modules
  - Quick Controls
  - Display & System
  - Accessories & Apps
  - Other & Reset
- Keeps appearance controls on the main page and Activation at the very end.
- Preserves every preference key, image action, Volume color action, apply action, and respring action from 1.1.18.
- Preserves the validated 1.1.18 renderer and the existing live $1 lifetime activation registry.
- Builds RootHide and rootless independently from the same source. Do not install both variants.

The customer-facing brand changes to Next Jailbreak, while the existing package identifier, preference domains, registry path, and license-token formula remain unchanged for upgrade and activation compatibility.

Run `python3 prepare_release.py <project-directory> <iphoneos-arm64|iphoneos-arm64e>` before packaging. The release workflow performs this step automatically and validates both DEBs.
