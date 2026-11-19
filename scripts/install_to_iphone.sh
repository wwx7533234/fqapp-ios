#!/usr/bin/env bash
# Builds the iOS app with automatic signing and installs it on the connected
# iPhone. Requires an Apple ID signed into Xcode → Settings → Accounts.
#
# Usage:
#   ./scripts/install_to_iphone.sh --check       # only report device/signing state
#   ./scripts/install_to_iphone.sh --launch-only # only launch the installed app
#   ./scripts/install_to_iphone.sh               # build, sign, install, launch
#
# Optional overrides:
#   TEAM_ID=XXXXXXXXXX   (defaults to the Apple Development identity)
#   BUNDLE_ID=com.you.fqapp
#   DEVICE_UDID=00008150-...
set -euo pipefail

# Finder/AppleScript launches may not inherit a UTF-8 locale; Xcode tooling and
# CocoaPods both expect one.
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_ID="${BUNDLE_ID:-com.weixiaoxun.tomatotown}"
TEAM_ID="${TEAM_ID:-}"
DEVICE_UDID="${DEVICE_UDID:-}"
CHECK_ONLY=0
LAUNCH_ONLY=0
case "${1:-}" in
  --check) CHECK_ONLY=1 ;;
  --launch-only) LAUNCH_ONLY=1 ;;
esac

FLUTTER="${FLUTTER:-$HOME/flutter/flutter/bin/flutter}"
if [ ! -x "$FLUTTER" ]; then
  FLUTTER="$(command -v flutter || true)"
fi
if [ -z "$FLUTTER" ]; then
  echo "错误：找不到 flutter。" >&2
  exit 1
fi

if [ -z "$DEVICE_UDID" ]; then
  DEVICE_UDID="$("$FLUTTER" devices --machine 2>/dev/null | python3 -c '
import json, sys
try:
    devices = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for d in devices:
    if d.get("targetPlatform", "").startswith("ios") and not d.get("emulator"):
        print(d.get("id", ""))
        break
')"
fi

if [ -z "$DEVICE_UDID" ]; then
  echo "错误：没有检测到已连接的真机 iPhone。请用数据线连接、解锁并点“信任此电脑”。" >&2
  exit 1
fi

# Prefer the team Xcode has an account for (the certificate's CN may carry a
# legacy/other team id even though its OU and the profile use the account team).
if [ -z "$TEAM_ID" ]; then
  TEAM_ID="$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null \
    | sed -n 's/.*teamID = \([A-Z0-9]\{10\}\).*/\1/p' | head -1)"
fi
if [ -z "$TEAM_ID" ]; then
  TEAM_ID="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*Apple Development:.*(\([A-Z0-9]\{10\}\)).*/\1/p' | head -1)"
fi

RUNNER_ID="$(grep -m1 'PRODUCT_BUNDLE_IDENTIFIER = ' "$APP_DIR/ios/Runner.xcodeproj/project.pbxproj" | sed 's/.*= \(.*\);/\1/' | tr -d ' ')"
echo "设备 UDID : $DEVICE_UDID"
echo "Bundle ID : ${BUNDLE_ID}（Runner target: ${RUNNER_ID}）"
if [ "$RUNNER_ID" != "$BUNDLE_ID" ]; then
  echo "错误：Runner target 的 Bundle ID 是 $RUNNER_ID，与脚本的 $BUNDLE_ID 不一致。" >&2
  echo "请先改 Runner target 的 PRODUCT_BUNDLE_IDENTIFIER（不要用全局命令行覆盖，会把 Pods 框架的 ID 也改掉）。" >&2
  exit 3
fi
if [ "$LAUNCH_ONLY" -eq 1 ]; then
  echo "==> 启动 番茄小镇..."
  xcrun devicectl device process launch --device "$DEVICE_UDID" "$BUNDLE_ID"
  exit $?
fi

echo "Team ID   : ${TEAM_ID:-（未找到 Apple Development 证书）}"

if [ -z "$TEAM_ID" ]; then
  echo
  echo "还没有可用的 Apple Development 证书。" >&2
  echo "请先在 Xcode 菜单 → Settings… → Accounts → + → Apple ID 登录，" >&2
  echo "登录成功后重新运行本脚本。" >&2
  exit 2
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
  echo "检查通过：可以开始构建并安装。"
  exit 0
fi

echo "==> xcodebuild（Release，自动签名）..."
xcodebuild \
  -workspace "$APP_DIR/ios/Runner.xcworkspace" \
  -scheme Runner \
  -configuration Release \
  -destination "id=$DEVICE_UDID" \
  -destination-timeout 45 \
  -derivedDataPath "$APP_DIR/build/device" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  build

APP="$APP_DIR/build/device/Build/Products/Release-iphoneos/Runner.app"
if [ ! -d "$APP" ]; then
  echo "错误：构建产物不存在：$APP" >&2
  exit 1
fi

echo "==> 校验签名..."
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> 安装到 iPhone..."
xcrun devicectl device install app --device "$DEVICE_UDID" "$APP"

echo "==> 启动 番茄小镇..."
xcrun devicectl device process launch --device "$DEVICE_UDID" "$BUNDLE_ID" || {
  echo "App 已安装但未能自动启动；请在 iPhone 上手动打开“番茄小镇”。" >&2
}

echo
echo "完成。若首次打开提示“未受信任的开发者”："
echo "  iPhone 设置 → 通用 → VPN 与设备管理 → 开发者 App → 你的 Apple ID → 信任。"
