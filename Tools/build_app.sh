#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
COMPATIBLE_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
if [[ -n "${SDKROOT:-}" ]]; then
  SDK_PATH="$SDKROOT"
elif [[ -d "$COMPATIBLE_SDK" ]]; then
  SDK_PATH="$COMPATIBLE_SDK"
else
  SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
fi
export SDKROOT="$SDK_PATH"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.build/swift-cache"
cd "$PROJECT_DIR"
swift build --disable-sandbox -c release
BIN_DIR="$(swift build --disable-sandbox -c release --show-bin-path)"

APP="$PROJECT_DIR/Build/HAM Trainer 3.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/HAMTrainer3" "$APP/Contents/MacOS/HAMTrainer3"
cp -R "$BIN_DIR/HAMTrainer3_HAMTrainer3.bundle" "$APP/Contents/Resources/"
cp "$PROJECT_DIR/HAMTrainer/Info.plist" "$APP/Contents/Info.plist"

ICON_WORK="$PROJECT_DIR/.build/app-icon"
rm -rf "$ICON_WORK"
mkdir -p "$ICON_WORK/HAMTrainer3.iconset" "$ICON_WORK/module-cache"
swiftc -sdk "$SDK_PATH" -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$ICON_WORK/module-cache" "$PROJECT_DIR/Tools/make_icon.swift" -o "$ICON_WORK/make-icon"
"$ICON_WORK/make-icon" "$ICON_WORK/icon-1024.png"
for spec in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" "512 icon_256x256@2x" "512 icon_512x512" "1024 icon_512x512@2x"; do
  pixels="${spec%% *}"; name="${spec#* }"
  sips -z "$pixels" "$pixels" "$ICON_WORK/icon-1024.png" --out "$ICON_WORK/HAMTrainer3.iconset/$name.png" >/dev/null
done
python3 "$PROJECT_DIR/Tools/make_icns.py" "$ICON_WORK/HAMTrainer3.iconset" "$APP/Contents/Resources/HAMTrainer3.icns"
codesign --force --deep --sign - "$APP"
echo "$APP"
