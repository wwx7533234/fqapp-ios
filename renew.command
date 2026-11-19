#!/bin/bash
# Double-clickable Terminal fallback for renewing 番茄小镇.
cd "$(dirname "$0")" || exit 1

echo "正在续签番茄小镇（构建 + 签名 + 安装）..."
./scripts/renew_fqapp.sh
status=$?

echo
if [ "$status" -ne 0 ]; then
  echo "续签失败。日志目录：$HOME/Library/Logs/fqapp"
  open "$HOME/Library/Logs/fqapp" 2>/dev/null
else
  echo "续签流程结束。"
fi
printf "按任意键关闭窗口..."
read -n 1 -s -r
echo
exit "$status"
