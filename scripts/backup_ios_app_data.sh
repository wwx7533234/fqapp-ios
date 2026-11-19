#!/usr/bin/env bash
# Back up an installed iOS app's data container before changing its Bundle ID.
#
# The Hive/AES key lives in the iOS Keychain, not in this backup. Recovery also
# needs the old Keychain access group and the old encrypted Documents files.
#
# Usage:
#   ./scripts/backup_ios_app_data.sh com.example.oldapp [destination]
#   DEVICE_UDID=... ./scripts/backup_ios_app_data.sh com.example.oldapp
set -u

BUNDLE_ID="${1:-}"
DEST="${2:-}"
if [ -z "$BUNDLE_ID" ]; then
  echo "用法：$0 <旧 App 的 Bundle ID> [备份目录]" >&2
  echo "例如：$0 com.example.oldapp" >&2
  exit 1
fi
if [ -z "$DEST" ]; then
  safe="$(printf '%s' "$BUNDLE_ID" | tr -c 'A-Za-z0-9._-' '_')"
  DEST="$HOME/fqapp-data-backup-${safe}-$(date '+%Y%m%d-%H%M%S')"
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
command -v python3 >/dev/null 2>&1 || { echo "错误：需要 python3。" >&2; exit 1; }
command -v xcrun >/dev/null 2>&1 || { echo "错误：需要 Xcode 命令行工具。" >&2; exit 1; }

mkdir -p "$DEST/Documents"
TMP="$(mktemp -t fqapp-files)"
trap 'rm -f "$TMP" "$TMP.names"' EXIT

if ! xcrun devicectl device info files \
  --device "$DEVICE_UDID" \
  --domain-type appDataContainer \
  --domain-identifier "$BUNDLE_ID" \
  --subdirectory Documents \
  --json-output "$TMP" \
  --timeout 60 >/dev/null 2>&1; then
  echo "错误：无法读取 $BUNDLE_ID 的 Documents。App 是否仍安装？" >&2
  exit 1
fi

python3 - "$TMP" > "$TMP.names" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as fh:
    data = json.load(fh)
for item in data.get('result', {}).get('files', []):
    name = item.get('name', '')
    if name:
        print(name)
PY

copied=0
failed=0
while IFS= read -r name; do
  [ -z "$name" ] && continue
  ok=0
  for attempt in 1 2 3; do
    if xcrun devicectl device copy from \
      --device "$DEVICE_UDID" \
      --domain-type appDataContainer \
      --domain-identifier "$BUNDLE_ID" \
      --source "Documents/$name" \
      --destination "$DEST/Documents/$name" \
      --timeout 120 >/dev/null 2>&1; then
      ok=1
      break
    fi
    sleep 1
  done
  if [ "$ok" -eq 1 ]; then
    copied=$((copied + 1))
  else
    echo "  跳过（无法读取）：Documents/$name" >&2
    failed=$((failed + 1))
  fi
done < "$TMP.names"

echo "Documents：$copied 个文件已备份，$failed 个读取失败。"

# Extra app state, when accessible. Failure here does not invalidate the Hive backup.
mkdir -p "$DEST/Library"
if xcrun devicectl device copy from \
  --device "$DEVICE_UDID" \
  --domain-type appDataContainer \
  --domain-identifier "$BUNDLE_ID" \
  --source "Library/Application Support" \
  --destination "$DEST/Library/Application Support" \
  --timeout 120 >/dev/null 2>&1; then
  echo "Library/Application Support：已备份。"
else
  echo "警告：Library/Application Support 读取失败；Documents 备份仍可用。" >&2
fi

echo
echo "备份目录：$DEST"
echo "注意：Keychain 密钥不在这个备份中；恢复还需要旧 App 的 Keychain access group。"
[ "$copied" -gt 0 ] || exit 1
