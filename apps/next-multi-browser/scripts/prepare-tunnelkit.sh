#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Vendor/TunnelKit"

rm -rf "$ROOT/Vendor"
mkdir -p "$ROOT/Vendor"
git clone --quiet https://github.com/partout-io/tunnelkit.git "$VENDOR"
git -C "$VENDOR" checkout --quiet f2c0fb079e2a318a4717d5fb8daa8f149174dadd

cat > "$VENDOR/Package.swift" <<'EOF'
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TunnelKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(name: "TunnelKit", targets: ["TunnelKit"]),
        .library(name: "TunnelKitOpenVPN", targets: ["TunnelKitOpenVPN"]),
        .library(name: "TunnelKitOpenVPNAppExtension", targets: ["TunnelKitOpenVPNAppExtension"]),
        .library(name: "TunnelKitLZO", targets: ["TunnelKitLZO"])
    ],
    dependencies: [
        .package(url: "https://github.com/SwiftyBeaver/SwiftyBeaver", from: "1.9.0"),
        .package(url: "https://github.com/passepartoutvpn/openssl-apple", from: "3.2.105")
    ],
    targets: [
        .target(name: "TunnelKit", dependencies: ["TunnelKitCore", "TunnelKitManager"]),
        .target(name: "TunnelKitCore", dependencies: ["__TunnelKitUtils", "CTunnelKitCore", "SwiftyBeaver"]),
        .target(name: "TunnelKitManager", dependencies: ["SwiftyBeaver"]),
        .target(name: "TunnelKitAppExtension", dependencies: ["TunnelKitCore"]),
        .target(name: "TunnelKitOpenVPN", dependencies: ["TunnelKitOpenVPNCore", "TunnelKitOpenVPNManager"]),
        .target(name: "TunnelKitOpenVPNCore", dependencies: ["TunnelKitCore", "CTunnelKitOpenVPNCore", "CTunnelKitOpenVPNProtocol"]),
        .target(name: "TunnelKitOpenVPNManager", dependencies: ["TunnelKitManager", "TunnelKitOpenVPNCore"]),
        .target(name: "TunnelKitOpenVPNProtocol", dependencies: ["TunnelKitOpenVPNCore", "CTunnelKitOpenVPNProtocol"]),
        .target(name: "TunnelKitOpenVPNAppExtension", dependencies: ["TunnelKitAppExtension", "TunnelKitOpenVPNCore", "TunnelKitOpenVPNManager", "TunnelKitOpenVPNProtocol"]),
        .target(
            name: "TunnelKitLZO",
            dependencies: [],
            exclude: ["lib/COPYING", "lib/Makefile", "lib/README.LZO", "lib/testmini.c"]
        ),
        .target(name: "CTunnelKitCore", dependencies: []),
        .target(name: "CTunnelKitOpenVPNCore", dependencies: []),
        .target(name: "CTunnelKitOpenVPNProtocol", dependencies: ["CTunnelKitCore", "CTunnelKitOpenVPNCore", "openssl-apple"]),
        .target(name: "__TunnelKitUtils", dependencies: [])
    ]
)
EOF

echo "Prepared TunnelKit OpenVPN-only package at $VENDOR"
