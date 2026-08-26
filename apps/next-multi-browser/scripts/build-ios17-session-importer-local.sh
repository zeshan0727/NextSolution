#!/bin/bash
set -euo pipefail

APP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$APP_ROOT"

command -v xcodebuild >/dev/null 2>&1 || {
  echo "Error: select full Xcode with xcode-select first."
  exit 1
}
command -v xcodegen >/dev/null 2>&1 || {
  echo "Error: install XcodeGen with brew install xcodegen."
  exit 1
}

echo "Preparing TunnelKit..."
bash scripts/prepare-tunnelkit.sh

echo "Preparing bundled VPN Gate fallback..."
python3 scripts/fetch-vpngate-seed.py Resources/VPNGateSeed.csv

echo "Generating Xcode project..."
xcodegen generate

echo "Building iOS 17 session importer..."
rm -rf build package NextMultiBrowser_iOS17_SessionImporter.tipa NextMultiBrowser_iOS17_SessionImporter.ipa
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
  build | tee session-transfer-build.log

APP_PATH="$(find build/Build/Products/Release-iphoneos -maxdepth 1 -name '*.app' -print -quit)"
test -n "$APP_PATH"
EXT_PATH="$APP_PATH/PlugIns/NextMultiBrowserVPN.appex"
test -d "$EXT_PATH"

/usr/bin/codesign --force --sign - --timestamp=none --generate-entitlement-der \
  --entitlements VPNExtension/VPN.entitlements "$EXT_PATH"
/usr/bin/codesign --force --sign - --timestamp=none --generate-entitlement-der \
  --entitlements App.entitlements "$APP_PATH"

mkdir -p package/Payload
cp -R "$APP_PATH" package/Payload/
(
  cd package
  /usr/bin/zip -qry ../NextMultiBrowser_iOS17_SessionImporter.tipa Payload
)
cp NextMultiBrowser_iOS17_SessionImporter.tipa NextMultiBrowser_iOS17_SessionImporter.ipa

echo
echo "Build completed:"
ls -lh NextMultiBrowser_iOS17_SessionImporter.tipa NextMultiBrowser_iOS17_SessionImporter.ipa
echo
echo "SHA-256:"
shasum -a 256 NextMultiBrowser_iOS17_SessionImporter.tipa NextMultiBrowser_iOS17_SessionImporter.ipa
