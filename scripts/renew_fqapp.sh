#!/usr/bin/env bash
# One-click renewal for the 番茄小镇 iOS app.
#
# It refreshes the 7-day free provisioning profile, rebuilds with automatic
# signing, installs on the connected iPhone and (when possible) launches it.
# It uses only the local Xcode account / keychain; no network service and no
# external agent is involved.
#
# Usage:
#   ./scripts/renew_fqapp.sh
#   (or double-click renew.command / 续签番茄小镇.app)
set -u

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$HOME/Library/Logs/fqapp"
STAMP="$(date '+%Y%m%d-%H%M%S')"
LOG="$LOG_DIR/renew-$STAMP.log"
OUT="$LOG_DIR/last-output.txt"
STATUS="$LOG_DIR/last-status.txt"
SUMMARY="$LOG_DIR/last-renewal.txt"
PROGRESS="$LOG_DIR/progress.txt"
mkdir -p "$LOG_DIR"
progress() { printf '%s|%s\n' "$1" "$2" > "$PROGRESS"; }
progress 2 "检查环境"
: > "$OUT"
echo "status=starting" > "$STATUS"

# Flutter, CocoaPods (this Mac installs it under ~/.gem) and Homebrew tools.
export PATH="$HOME/flutter/flutter/bin:$HOME/.gem/ruby/2.6.0/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
# Launched from Finder/AppleScript there is often no UTF-8 locale. CocoaPods
# 1.15 on system Ruby 2.6 crashes with "Unicode Normalization not appropriate"
# unless LANG/LC_ALL are UTF-8.
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
# System Ruby 2.6 + CocoaPods 1.15 needs logger preloaded; harmless otherwise.
export RUBYOPT="-rlogger"

# Mirror everything to the log and to last-output.txt (used for diagnostics).
exec > >(tee -a "$LOG" "$OUT") 2>&1

fail() {
  local message="$1"
  local state="${2:-failed}"
  echo
  echo "❌ $message"
  echo "status=$state" > "$STATUS"
  echo "error=$message" >> "$STATUS"
  echo "$message" > "$SUMMARY"
  echo "日志：$LOG"
  exit 1
}

progress 5 "检查环境"
echo "============================================================"
echo " 番茄小镇 · iOS 续签"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo " 项目：$APP_DIR"
echo " 日志：$LOG"
echo "============================================================"
echo

[ -d "$APP_DIR/ios/Runner.xcworkspace" ] || fail "找不到 ios/Runner.xcworkspace，项目目录不完整。"
command -v xcodebuild >/dev/null 2>&1 || fail "找不到 xcodebuild，请确认已安装 Xcode。"
command -v xcrun >/dev/null 2>&1 || fail "找不到 xcrun，请确认已安装 Xcode。"
command -v python3 >/dev/null 2>&1 || fail "找不到 python3。"
command -v flutter >/dev/null 2>&1 || fail "找不到 flutter（PATH: $PATH）。"

# CocoaPods only needs to run when Pods is missing or the lock files disagree.
# Comparing file contents avoids a needless `pod install` on every run (which
# is also the path that used to fail under a non-UTF-8 Finder environment).
POD="$(command -v pod 2>/dev/null || true)"
MANIFEST="$APP_DIR/ios/Pods/Manifest.lock"
PODFILE_LOCK="$APP_DIR/ios/Podfile.lock"
NEED_PODS=0
if [ ! -d "$APP_DIR/ios/Pods" ] || [ ! -f "$MANIFEST" ] || [ ! -f "$PODFILE_LOCK" ]; then
  NEED_PODS=1
elif [ "$APP_DIR/ios/Podfile" -nt "$MANIFEST" ]; then
  NEED_PODS=1
elif ! cmp -s "$PODFILE_LOCK" "$MANIFEST"; then
  NEED_PODS=1
fi

if [ "$NEED_PODS" -eq 1 ]; then
  if [ -z "$POD" ]; then
    fail "CocoaPods 依赖需要更新，但找不到 pod 命令。请在终端运行一次 pod install。"
  fi
  echo "==> 更新 CocoaPods 依赖..."
  ( cd "$APP_DIR/ios" && "$POD" install ) || fail "CocoaPods 安装失败。"
  echo
else
  echo "==> CocoaPods 依赖已是最新，跳过 pod install。"
  echo
fi
progress 12 "依赖就绪"

progress 20 "检查 iPhone 与证书"
echo "==> 检查 iPhone 与签名证书..."
if ! "$APP_DIR/scripts/install_to_iphone.sh" --check; then
  fail "设备或签名预检失败。请确认：iPhone 已连接并解锁、Xcode 已登录 Apple ID。"
fi
echo

progress 30 "构建与签名"
echo "==> 构建 + 自动签名 + 安装（通常 1–3 分钟）..."
if ! "$APP_DIR/scripts/install_to_iphone.sh"; then
  if grep -q "needs to be unlocked\|Timed out waiting for all destinations" "$OUT"; then
    fail "iPhone 处于锁屏状态。请解锁手机并保持亮屏，然后重新运行续签。" "failed-unlock"
  fi
  fail "构建、签名或安装失败，详见日志。"
fi
progress 96 "检查启动结果"
echo

APP="$APP_DIR/build/device/Build/Products/Release-iphoneos/Runner.app"
EXPIRY="未知"
BUNDLE="com.weixiaoxun.tomatotown"
DISPLAY="番茄小镇"
if [ -f "$APP/embedded.mobileprovision" ]; then
  TMPP="$(mktemp -t fqapp-profile)"
  if security cms -D -i "$APP/embedded.mobileprovision" > "$TMPP" 2>/dev/null; then
    EXPIRY="$(/usr/libexec/PlistBuddy -c 'Print :ExpirationDate' "$TMPP" 2>/dev/null || true)"
    [ -n "$EXPIRY" ] || EXPIRY="未知"
  fi
  rm -f "$TMPP"
fi
if [ -f "$APP/Info.plist" ]; then
  BUNDLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist" 2>/dev/null || echo "$BUNDLE")"
  DISPLAY="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$APP/Info.plist" 2>/dev/null || echo "$DISPLAY")"
fi

# Distinguish the common launch outcomes so the App can show the right hint.
if grep -q "not been explicitly trusted" "$OUT"; then
  STATE="needs-trust"
elif grep -q "Locked" "$OUT"; then
  STATE="needs-unlock"
elif grep -q "未能自动启动" "$OUT"; then
  STATE="installed"
else
  STATE="ok"
fi

{
  echo "status=$STATE"
  echo "expiry=$EXPIRY"
  echo "bundle=$BUNDLE"
  echo "display=$DISPLAY"
  echo "renewed_at=$(date '+%Y-%m-%d %H:%M:%S')"
} > "$STATUS"

cat > "$SUMMARY" <<EOF
续签时间：$(date '+%Y-%m-%d %H:%M:%S')
显示名称：$DISPLAY
Bundle ID：$BUNDLE
描述文件到期：$EXPIRY
状态：$STATE
EOF

progress 100 "完成"
cat "$SUMMARY"
echo
case "$STATE" in
  needs-trust)
    echo "⚠️ 已安装，但还需要在 iPhone 上信任一次："
    echo "   设置 → 通用 → VPN 与设备管理 → 开发者 App → Apple ID → 信任"
    echo "   然后打开“番茄小镇”。"
    ;;
  needs-unlock)
    echo "⚠️ 已安装；手机当时锁屏，解锁后打开“番茄小镇”即可。"
    ;;
  installed)
    echo "⚠️ 已安装；如未自动打开，请解锁后手动打开“番茄小镇”。"
    ;;
  ok)
    echo "✅ 完成，App 已启动。"
    ;;
esac
echo
echo "日志：$LOG"
exit 0
