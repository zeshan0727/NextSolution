#!/bin/bash
set -euo pipefail

APP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$APP_ROOT"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Error: Xcode command-line tools are unavailable."
  echo "Install/open Xcode, then run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Error: XcodeGen is required."
  echo "Install it with: brew install xcodegen"
  exit 1
fi

echo "Preparing TunnelKit..."
bash scripts/prepare-tunnelkit.sh

echo "Preparing bundled VPN Gate fallback..."
python3 scripts/fetch-vpngate-seed.py Resources/VPNGateSeed.csv

echo "Generating Xcode project..."
xcodegen generate

echo "Building unsigned iOS 17 device app..."
rm -rf build package NextMultiBrowser_iOS17_Test.tipa NextMultiBrowser_iOS17_Test.ipa
set -o pipefail
xcodebuild \
  -project NextMultiBrowser.xcodeproj \
  -scheme NextMultiBrowser \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' \
  build | tee ios17-build.log

APP_PATH="$(find build/Build/Products/Release-iphoneos -maxdepth 1 -name '*.app' -print -quit)"
if [[ -z "$APP_PATH" ]]; then
  echo "Error: built app was not found."
  exit 1
fi

EXT_PATH="$APP_PATH/PlugIns/NextMultiBrowserVPN.appex"
if [[ ! -d "$EXT_PATH" ]]; then
  echo "Error: VPN extension was not found at $EXT_PATH"
  exit 1
fi

echo "Ad-hoc signing VPN extension and app..."
/usr/bin/codesign --force --sign - --timestamp=none --generate-entitlement-der \
  --entitlements VPNExtension/VPN.entitlements "$EXT_PATH"
/usr/bin/codesign --force --sign - --timestamp=none --generate-entitlement-der \
  --entitlements App.entitlements "$APP_PATH"

echo "Packaging TIPA and IPA..."
mkdir -p package/Payload
cp -R "$APP_PATH" package/Payload/
(
  cd package
  /usr/bin/zip -qry ../NextMultiBrowser_iOS17_Test.tipa Payload
)
cp NextMultiBrowser_iOS17_Test.tipa NextMultiBrowser_iOS17_Test.ipa

echo
echo "Build completed:"
ls -lh NextMultiBrowser_iOS17_Test.tipa NextMultiBrowser_iOS17_Test.ipa
echo
echo "SHA-256:"
shasum -a 256 NextMultiBrowser_iOS17_Test.tipa NextMultiBrowser_iOS17_Test.ipa
