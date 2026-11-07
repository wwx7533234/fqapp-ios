#!/usr/bin/env bash
# Packages the built iOS products into dist/:
#   - fqapp-ios-unsigned.ipa  (device build; must be signed before installing)
#   - fqapp-ios-simulator.zip (runnable in Xcode Simulator, no signing)
#   - SHA256SUMS
#
# Run scripts/build_rust_ios.sh, pod install and the two flutter builds first.
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$APP_DIR/dist"
SIM_APP="$APP_DIR/build/ios/iphonesimulator/Runner.app"
ARCHIVE_APP="$APP_DIR/build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app"
DEVICE_APP="$APP_DIR/build/ios/iphoneos/Runner.app"

mkdir -p "$DIST"

if [ -d "$ARCHIVE_APP" ]; then
  DEVICE_SOURCE="$ARCHIVE_APP"
elif [ -d "$DEVICE_APP" ]; then
  DEVICE_SOURCE="$DEVICE_APP"
else
  echo "错误：找不到设备构建产物（先跑 flutter build ipa --release --no-codesign）。" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/Payload"
ditto "$DEVICE_SOURCE" "$WORK/Payload/Runner.app"
( cd "$WORK" && zip -qry "$DIST/fqapp-ios-unsigned.ipa" Payload )
echo "==> dist/fqapp-ios-unsigned.ipa"

if [ -d "$SIM_APP" ]; then
  ditto --norsrc --noextattr -c -k --keepParent "$SIM_APP" "$DIST/fqapp-ios-simulator.zip"
  echo "==> dist/fqapp-ios-simulator.zip"
else
  echo "警告：没有模拟器 App，跳过 dist/fqapp-ios-simulator.zip" >&2
fi

# Source archive: the iOS runner, Swift hosts, Rust cache module and tests.
# Build products and dependency caches are deliberately excluded.
rm -f "$DIST/fqapp-ios-source.zip"
( cd "$APP_DIR" && zip -qry "$DIST/fqapp-ios-source.zip" . \
  -x "build/*" "rust/target/*" ".dart_tool/*" "ios/Pods/*" "ios/.symlinks/*" \
     "dist/*" ".idea/*" "*.iml" "*.log" ".DS_Store" )
echo "==> dist/fqapp-ios-source.zip"

( cd "$DIST" && shasum -a 256 *.ipa *.zip *.pdf 2>/dev/null > SHA256SUMS || true )
ls -lh "$DIST"
