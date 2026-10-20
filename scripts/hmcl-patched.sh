#!/usr/bin/env bash
#
# Linux / macOS 包装启动脚本：不改 shell 配置，只在本次启动时注入补丁。
#
# 用法：
#   ./hmcl-patched.sh /path/to/HMCL.sh [HMCL 参数...]
#   ./hmcl-patched.sh /path/to/hmcl [HMCL 参数...]
#
# 说明：官方 HMCL.sh / deb 启动脚本都会读取 HMCL_JAVA_OPTS 环境变量；
#       这里设置好之后再 exec 原始启动文件。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_JAR="${SCRIPT_DIR}/../dist/hmcl-region-patch.jar"

if [ $# -lt 1 ]; then
    echo "用法：$0 <HMCL 启动文件（HMCL.sh 或 hmcl 可执行文件）> [HMCL 参数...]" >&2
    exit 2
fi

if [ ! -f "$PATCH_JAR" ]; then
    echo "错误：找不到 $PATCH_JAR，请先运行 ./build.sh" >&2
    exit 1
fi
PATCH_JAR="$(cd "$(dirname "$PATCH_JAR")" && pwd)/$(basename "$PATCH_JAR")"

if [[ "$PATCH_JAR" == *" "* ]]; then
    echo "错误：注入包路径含空格（$PATCH_JAR）。HMCL.sh 的参数展开不支持空格路径，" >&2
    echo "      请把项目放到无空格目录，或运行 scripts/install-linux.sh --copy-jar。" >&2
    exit 1
fi

HMCL_LAUNCHER="$1"
shift

# 保留用户已有的 HMCL_JAVA_OPTS；没有则补上 HMCL.sh 的默认 JVM 参数
if [ -z "${HMCL_JAVA_OPTS:-}" ]; then
    HMCL_JAVA_OPTS="-XX:MinHeapFreeRatio=5 -XX:MaxHeapFreeRatio=15 -XX:G1PeriodicGCInterval=900000 -XX:G1PeriodicGCSystemLoadThreshold=0.6 -XX:+UseStringDeduplication"
fi
export HMCL_JAVA_OPTS="$HMCL_JAVA_OPTS -javaagent:$PATCH_JAR"

exec "$HMCL_LAUNCHER" "$@"
