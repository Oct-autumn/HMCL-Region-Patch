#!/usr/bin/env bash
#
# 为 Linux / macOS 上的 HMCL 安装区域补丁。
#
# 原理：官方 HMCL.sh（以及 deb 包里的启动脚本）会读取 HMCL_JAVA_OPTS 环境变量，
# 把其中的参数原样传给 JVM。本脚本把 -javaagent 参数写入 shell 启动配置。
#
# 用法：
#   ./install-linux.sh            写入 ~/.bashrc（默认）
#   ./install-linux.sh --print    只打印要添加的配置，不修改文件
#   ./install-linux.sh --jar PATH 指定注入包路径
#   ./install-linux.sh --rc FILE  写入指定配置文件（例如 ~/.zshrc）
#   ./install-linux.sh --copy-jar 把注入包复制到 ~/.local/share/hmcl-region-patch/ 再使用
#
# 注意：HMCL.sh 展开 HMCL_JAVA_OPTS 时不会处理引号，路径中不能有空格；
#       如果当前路径含空格，脚本会自动复制到 ~/.local/share/hmcl-region-patch/。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH_JAR="${ROOT_DIR}/dist/hmcl-region-patch.jar"
RC_FILE="${HOME}/.bashrc"
PRINT_ONLY=0
COPY_JAR=0

while [ $# -gt 0 ]; do
    case "$1" in
        --print)     PRINT_ONLY=1; shift ;;
        --jar)       PATCH_JAR="${2:?--jar 需要路径}"; shift 2 ;;
        --rc)        RC_FILE="${2:?--rc 需要文件路径}"; shift 2 ;;
        --copy-jar)  COPY_JAR=1; shift ;;
        -h|--help)
            sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "未知参数：$1" >&2; exit 2 ;;
    esac
done

if [ ! -f "$PATCH_JAR" ]; then
    echo "错误：找不到注入包 $PATCH_JAR，请先运行 ./build.sh" >&2
    exit 1
fi
PATCH_JAR="$(cd "$(dirname "$PATCH_JAR")" && pwd)/$(basename "$PATCH_JAR")"

# HMCL.sh 用未加引号的变量展开，含空格的路径会断掉
if [ "$COPY_JAR" -eq 1 ] || [[ "$PATCH_JAR" == *" "* ]]; then
    install_dir="${HOME}/.local/share/hmcl-region-patch"
    mkdir -p "$install_dir"
    cp -f "$PATCH_JAR" "$install_dir/hmcl-region-patch.jar"
    PATCH_JAR="$install_dir/hmcl-region-patch.jar"
    echo "已复制注入包到：$PATCH_JAR"
fi

MARKER_BEGIN="# >>> hmcl-region-patch >>>"
MARKER_END="# <<< hmcl-region-patch <<<"

CONFIG_BLOCK=$(cat <<EOF
${MARKER_BEGIN}
# 由 hmcl-region-patch 安装脚本生成；卸载请运行 scripts/uninstall-linux.sh
if [ -z "\${HMCL_JAVA_OPTS:-}" ]; then
    export HMCL_JAVA_OPTS="-XX:MinHeapFreeRatio=5 -XX:MaxHeapFreeRatio=15 -XX:G1PeriodicGCInterval=900000 -XX:G1PeriodicGCSystemLoadThreshold=0.6 -XX:+UseStringDeduplication"
fi
export HMCL_JAVA_OPTS="\$HMCL_JAVA_OPTS -javaagent:${PATCH_JAR}"
${MARKER_END}
EOF
)

if [ "$PRINT_ONLY" -eq 1 ]; then
    echo "把下面这段追加到 $RC_FILE 即可（或在当前 shell 里 source 它）："
    echo
    echo "$CONFIG_BLOCK"
    exit 0
fi

# 先删掉旧的标记块（幂等），再追加新块
if [ -f "$RC_FILE" ]; then
    sed -i.bak '/^# >>> hmcl-region-patch >>>/,/^# <<< hmcl-region-patch <<</d' "$RC_FILE"
    rm -f "${RC_FILE}.bak"
else
    touch "$RC_FILE"
fi
printf '\n%s\n' "$CONFIG_BLOCK" >> "$RC_FILE"

echo "已写入 $RC_FILE："
echo "  -javaagent:${PATCH_JAR}"
echo
echo "接下来：source $RC_FILE 或重新打开终端，然后正常启动 HMCL 即可。"
echo "日志在注入包同目录的 hmcl-region-patch.log。"
echo "卸载：./uninstall-linux.sh --rc $RC_FILE"
