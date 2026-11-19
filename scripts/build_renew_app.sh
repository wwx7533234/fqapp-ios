#!/usr/bin/env bash
# Builds "续签番茄小镇.app" (Swift/AppKit progress UI) in ~/Applications.
#
# The app runs scripts/renew_fqapp.sh asynchronously and renders live progress,
# step state and the log. It contains no signing material.
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$HOME/Applications/续签番茄小镇.app"
SRC="$APP_DIR/scripts/renew_app.swift"
ICON_SRC="$APP_DIR/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[ -f "$SRC" ] || { echo "错误：找不到 $SRC" >&2; exit 1; }
[ -f "$ICON_SRC" ] || { echo "错误：找不到应用图标 $ICON_SRC" >&2; exit 1; }
command -v xcrun >/dev/null || { echo "错误：找不到 xcrun（需要 Xcode 命令行工具）。" >&2; exit 1; }

echo "==> 准备 Swift 源码..."
sed "s|__PROJECT_DIR__|$APP_DIR|g" "$SRC" > "$WORK/RenewApp.swift"

echo "==> 编译 Swift/AppKit 应用..."
rm -rf "$DEST"
mkdir -p "$DEST/Contents/MacOS" "$DEST/Contents/Resources"
xcrun --sdk macosx swiftc \
  -parse-as-library \
  -swift-version 5 \
  -O \
  "$WORK/RenewApp.swift" \
  -o "$DEST/Contents/MacOS/RenewApp"

echo "==> 生成应用图标..."
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for spec in "16 icon_16x16.png" "32 icon_16x16@2x.png" "32 icon_32x32.png" \
            "64 icon_32x32@2x.png" "128 icon_128x128.png" "256 icon_128x128@2x.png" \
            "256 icon_256x256.png" "512 icon_256x256@2x.png" "512 icon_512x512.png" \
            "1024 icon_512x512@2x.png"; do
  set -- $spec
  sips -z "$1" "$1" "$ICON_SRC" --out "$ICONSET/$2" >/dev/null 2>&1
done
if iconutil -c icns "$ICONSET" -o "$DEST/Contents/Resources/AppIcon.icns" 2>/dev/null; then
  echo "    图标已应用"
else
  echo "    警告：图标生成失败，保留系统默认图标"
fi

echo "==> 写入应用信息..."
cat > "$DEST/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>zh_CN</string>
	<key>CFBundleDisplayName</key>
	<string>续签番茄小镇</string>
	<key>CFBundleExecutable</key>
	<string>RenewApp</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon.icns</string>
	<key>CFBundleIdentifier</key>
	<string>com.weixiaoxun.renew-fqapp</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>续签番茄小镇</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>2.0</string>
	<key>CFBundleVersion</key>
	<string>2</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
PLIST

chmod +x "$DEST/Contents/MacOS/RenewApp"
xattr -cr "$DEST" 2>/dev/null || true

echo "==> ad-hoc 签名..."
codesign --force --deep --sign - "$DEST" >/dev/null 2>&1
if ! codesign --verify --deep --strict "$DEST"; then
  echo "错误：应用签名校验失败。" >&2
  exit 1
fi

# Desktop is iCloud/File Provider synced on this Mac: adding FinderInfo to an
# app bundle there breaks codesign. Keep the signed app in ~/Applications and
# expose a symlink on the Desktop.
echo "==> 创建桌面入口..."
DESKTOP_LINK="$HOME/Desktop/续签番茄小镇.app"
rm -rf "$DESKTOP_LINK" 2>/dev/null || true
ln -sfn "$DEST" "$DESKTOP_LINK"

echo "==> 完成：$DEST"
echo "    桌面入口：$DESKTOP_LINK"
/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" "$DEST/Contents/Info.plist" 2>/dev/null || true
