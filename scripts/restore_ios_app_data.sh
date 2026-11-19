#!/usr/bin/env bash
# Restore a data backup created by backup_ios_app_data.sh into the newly
# installed app's container. The Keychain key migration must be prepared
# separately; see RECOVERY.md.
#
# Usage:
#   ./scripts/restore_ios_app_data.sh <backup-dir> <new.bundle.id>
#   DEVICE_UDID=... ./scripts/restore_ios_app_data.sh <backup-dir> <new.bundle.id>
set -u

BACKUP="${1:-}"
NEW_ID="${2:-}"
if [ -z "$BACKUP" ] || [ -z "$NEW_ID" ]; then
  echo "用法：$0 <备份目录> <新 App 的 Bundle ID>" >&2
  echo "例如：$0 ~/fqapp-data-backup-old com.example.newapp" >&2
  exit 1
fi
if [ ! -d "$BACKUP/Documents" ]; then
  echo "错误：备份目录里没有 Documents：$BACKUP" >&2
  exit 1
fi

FLUTTER="${FLUTTER:-$HOME/flutter/flutter/bin/flutter}"
if [ ! -x "$FLUTTER" ]; then
  FLUTTER="$(command -v flutter 2>/dev/null || true)"
fi
if [ -z "${DEVICE_UDID:-}" ]; then
  if [ -z "$FLUTTER" ]; then
    echo "错误：找不到 flutter，请用 DEVICE_UDID=... 指定设备。" >&2
    exit 1
  fi
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
if [ -z "${DEVICE_UDID:-}" ]; then
  echo "错误：没有检测到已连接的真机 iPhone。" >&2
  exit 1
fi

echo "警告：请先安装带旧 Keychain access group 的恢复构建，并确保新 App 尚未启动。"
echo "否则新 App 可能把读不出的加密盒子当成空盒删除。"

copied=0
failed=0
while IFS= read -r file; do
  [ -z "$file" ] && continue
  rel="${file#"$BACKUP"/}"
  ok=0
  for attempt in 1 2 3; do
    if xcrun devicectl device copy to \
      --device "$DEVICE_UDID" \
      --domain-type appDataContainer \
      --domain-identifier "$NEW_ID" \
      --source "$file" \
      --destination "$rel" \
      --timeout 120 >/dev/null 2>&1; then
      ok=1
      break
    fi
    sleep 1
  done
  if [ "$ok" -eq 1 ]; then
    copied=$((copied + 1))
  else
    echo "  失败：$rel" >&2
    failed=$((failed + 1))
  fi
done < <(find "$BACKUP/Documents" -type f | sort)

echo "Documents：$copied 个文件已恢复，$failed 个失败。"
[ "$failed" -eq 0 ] && [ "$copied" -gt 0 ]
