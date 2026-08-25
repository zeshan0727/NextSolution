#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="${RUNNER_TEMP:-/tmp}/nextdroid-test1"
UTM_VERSION="4.7.5"
APP_ID="com.nextjailbreak.nextdroid.test1"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/unpacked"

curl --fail --location --retry 3 \
    --output "$WORK_DIR/UTM-HV.ipa" \
    "https://github.com/utmapp/UTM/releases/download/v${UTM_VERSION}/UTM-HV.ipa"
unzip -q "$WORK_DIR/UTM-HV.ipa" -d "$WORK_DIR/unpacked"

APP_PATH="$WORK_DIR/unpacked/Payload/UTM.app"
APP_EXECUTABLE="$APP_PATH/UTM"
FRAMEWORKS_PATH="$APP_PATH/Frameworks"
mkdir -p "$FRAMEWORKS_PATH"

xcrun --sdk iphoneos clang \
    -arch arm64 \
    -miphoneos-version-min=16.0 \
    -fobjc-arc \
    -fmodules \
    -dynamiclib \
    "$ROOT_DIR/Bootstrap.m" \
    -framework Foundation \
    -framework UIKit \
    -framework Security \
    -o "$FRAMEWORKS_PATH/NextDroidBootstrap.dylib" \
    -install_name "@executable_path/Frameworks/NextDroidBootstrap.dylib"

git clone --depth 1 https://github.com/Tyilo/insert_dylib.git "$WORK_DIR/insert_dylib"
clang "$WORK_DIR/insert_dylib/insert_dylib/main.c" -o "$WORK_DIR/insert_dylib_tool"
"$WORK_DIR/insert_dylib_tool" \
    --inplace \
    --strip-codesig \
    --all-yes \
    "@executable_path/Frameworks/NextDroidBootstrap.dylib" \
    "$APP_EXECUTABLE"

set_plist_string() {
    local key="$1"
    local value="$2"
    if ! /usr/libexec/PlistBuddy -c "Set :${key} ${value}" "$APP_PATH/Info.plist"; then
        /usr/libexec/PlistBuddy -c "Add :${key} string ${value}" "$APP_PATH/Info.plist"
    fi
}

set_plist_string CFBundleDisplayName "NextDroid Test"
set_plist_string CFBundleName "NextDroid"
set_plist_string CFBundleIdentifier "$APP_ID"
set_plist_string CFBundleShortVersionString "0.1"
set_plist_string CFBundleVersion "1"
rm -rf "$APP_PATH/_CodeSignature"

if ! command -v ldid >/dev/null 2>&1; then
    brew install ldid
fi
ldid -S "$FRAMEWORKS_PATH/NextDroidBootstrap.dylib"
ldid -S"$ROOT_DIR/NextDroidHV.entitlements" -I"$APP_ID" "$APP_EXECUTABLE"

OUTPUT_DIR="$ROOT_DIR/output"
mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR/NextDroid_Android11_Test1.tipa"
(
    cd "$WORK_DIR/unpacked"
    zip -qry "$OUTPUT_DIR/NextDroid_Android11_Test1.tipa" Payload \
        -x "._*" "*/.DS_Store" "*/__MACOSX/*"
)

unzip -t "$OUTPUT_DIR/NextDroid_Android11_Test1.tipa"
shasum -a 256 "$OUTPUT_DIR/NextDroid_Android11_Test1.tipa" | tee "$OUTPUT_DIR/NextDroid_Android11_Test1.sha256"
