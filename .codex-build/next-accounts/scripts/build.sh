#!/bin/bash
set -euo pipefail

APP_NAME="NextAccounts"
BUILD_ROOT="${PWD}/build"
PAYLOAD_DIR="${BUILD_ROOT}/Payload"
APP_DIR="${PAYLOAD_DIR}/${APP_NAME}.app"
SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
ICON_SOURCE="${BUILD_ROOT}/AppIconSource.png"

rm -rf "${BUILD_ROOT}"
mkdir -p "${APP_DIR}"

xcrun --sdk iphoneos swiftc \
  -sdk "${SDK_PATH}" \
  -target arm64-apple-ios16.0 \
  -parse-as-library \
  -module-name "${APP_NAME}" \
  -O \
  -whole-module-optimization \
  -framework SwiftUI \
  -framework UIKit \
  -framework Foundation \
  -framework Security \
  -Xlinker -dead_strip \
  Sources/*.swift \
  -o "${APP_DIR}/${APP_NAME}"

cp Resources/Info.plist "${APP_DIR}/Info.plist"
cp Resources/Seed.template.json "${APP_DIR}/Seed.json"

if [[ -f Resources/AppIcon.png ]]; then
  cp Resources/AppIcon.png "${ICON_SOURCE}"
elif [[ -f Resources/AppIcon.b64 ]]; then
  openssl base64 -d -A -in Resources/AppIcon.b64 -out "${BUILD_ROOT}/AppIconSource.jpg"
  sips -s format png "${BUILD_ROOT}/AppIconSource.jpg" --out "${ICON_SOURCE}" >/dev/null
else
  echo "Missing app icon source" >&2
  exit 1
fi

sips -s format png -z 1024 1024 "${ICON_SOURCE}" --out "${APP_DIR}/AppIcon1024.png" >/dev/null
sips -s format png -z 120 120 "${ICON_SOURCE}" --out "${APP_DIR}/AppIcon60@2x.png" >/dev/null
sips -s format png -z 180 180 "${ICON_SOURCE}" --out "${APP_DIR}/AppIcon60@3x.png" >/dev/null
sips -s format png -z 152 152 "${ICON_SOURCE}" --out "${APP_DIR}/AppIcon76@2x.png" >/dev/null
sips -s format png -z 167 167 "${ICON_SOURCE}" --out "${APP_DIR}/AppIcon83.5@2x.png" >/dev/null

chmod 0755 "${APP_DIR}/${APP_NAME}"
plutil -lint "${APP_DIR}/Info.plist"
file "${APP_DIR}/${APP_NAME}"

(
  cd "${BUILD_ROOT}"
  /usr/bin/zip -qry "../NextAccounts_1.0.0.tipa" Payload
)

echo "Built ${PWD}/NextAccounts_1.0.0.tipa"
