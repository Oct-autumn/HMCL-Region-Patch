#!/usr/bin/env bash
#
# 卸载 Linux / macOS 上的 HMCL 区域补丁。
#
# 用法：
#   ./uninstall-linux.sh              从 ~/.bashrc 移除
#   ./uninstall-linux.sh --rc FILE    从指定配置文件移除（例如 ~/.zshrc）
set -euo pipefail

RC_FILE="${HOME}/.bashrc"
while [ $# -gt 0 ]; do
    case "$1" in
        --rc) RC_FILE="${2:?--rc 需要文件路径}"; shift 2 ;;
        -h|--help)
            sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "未知参数：$1" >&2; exit 2 ;;
    esac
done

if [ ! -f "$RC_FILE" ]; then
    echo "没有找到 $RC_FILE，无需卸载。"
    exit 0
fi

if ! grep -q "^# >>> hmcl-region-patch >>>" "$RC_FILE"; then
    echo "$RC_FILE 中没有 hmcl-region-patch 的配置，无需卸载。"
    exit 0
fi

sed -i.bak '/^# >>> hmcl-region-patch >>>/,/^# <<< hmcl-region-patch <<</d' "$RC_FILE"
rm -f "${RC_FILE}.bak"
echo "已从 $RC_FILE 移除 hmcl-region-patch 配置。重新打开终端后生效。"
