#!/usr/bin/env bash
#
# HMCL Region Patch 构建脚本（Linux / macOS / WSL）
#
# 用法：
#   ./build.sh                 仅构建 dist/hmcl-region-patch.jar
#   ./build.sh --test          构建后运行自测（SelfTest）
#   ./build.sh --verify <jar>  构建后用真实 HMCL jar 做端到端验证
#
# 依赖：JDK 17+（java / javac / jar 在 PATH 中）、curl 或 wget（首次下载 ASM）
# 说明：ASM 默认从 Maven Central 下载并缓存在 build/deps/，
#       国内网络慢时可以用 ASM_REPO 环境变量换成镜像地址。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT_DIR/build"
DIST_DIR="$ROOT_DIR/dist"
ASM_VERSION="${ASM_VERSION:-9.9}"
ASM_REPO="${ASM_REPO:-https://repo1.maven.org/maven2}"
AGENT_JAR="$DIST_DIR/hmcl-region-patch.jar"

RUN_TEST=0
VERIFY_JAR=""
while [ $# -gt 0 ]; do
    case "$1" in
        --test)   RUN_TEST=1; shift ;;
        --verify) VERIFY_JAR="${2:-}"; shift 2 ;;
        -h|--help)
            sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "未知参数: $1" >&2; exit 2 ;;
    esac
done

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "错误：找不到 $1，请安装 JDK 17+ 并加入 PATH" >&2
        exit 1
    fi
}

download_dep() {
    local name="$1"
    local target="$BUILD_DIR/deps/$name-$ASM_VERSION.jar"
    if [ -f "$target" ]; then
        return
    fi
    mkdir -p "$BUILD_DIR/deps"
    local url="$ASM_REPO/org/ow2/asm/$name/$ASM_VERSION/$name-$ASM_VERSION.jar"
    echo "下载 $name $ASM_VERSION ..."
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 -o "$target" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$target" "$url"
    else
        echo "错误：需要 curl 或 wget 下载 ASM" >&2
        exit 1
    fi
}

require_command java
require_command javac
require_command jar

# 检查 JDK 版本不低于 17
JAVA_MAJOR="$(java -version 2>&1 | awk -F'"' '/version/ {print $2}' | cut -d. -f1)"
if [ "${JAVA_MAJOR:-0}" -lt 17 ]; then
    echo "错误：需要 JDK 17+，当前为 ${JAVA_MAJOR:-未知}" >&2
    exit 1
fi

download_dep asm
download_dep asm-tree

echo "== 编译主代码 =="
rm -rf "$BUILD_DIR/classes"
mkdir -p "$BUILD_DIR/classes"
find "$ROOT_DIR/src/main/java" -name '*.java' > "$BUILD_DIR/sources.txt"
javac --release 17 -encoding UTF-8 -cp "$BUILD_DIR/deps/asm-$ASM_VERSION.jar:$BUILD_DIR/deps/asm-tree-$ASM_VERSION.jar" \
    -d "$BUILD_DIR/classes" @"$BUILD_DIR/sources.txt"

echo "== 合并 ASM 依赖 =="
rm -rf "$BUILD_DIR/shade"
mkdir -p "$BUILD_DIR/shade"
# 用 jar 命令解压，避免依赖 unzip
(cd "$BUILD_DIR/shade" && jar xf "$BUILD_DIR/deps/asm-$ASM_VERSION.jar" && jar xf "$BUILD_DIR/deps/asm-tree-$ASM_VERSION.jar")
# 去掉会冲突的元数据：ASM 自己的 module-info 和 META-INF
rm -rf "$BUILD_DIR/shade/module-info.class" "$BUILD_DIR/shade/META-INF"
cp -R "$BUILD_DIR/classes/." "$BUILD_DIR/shade/"

echo "== 生成注入包 =="
mkdir -p "$DIST_DIR"
cat > "$BUILD_DIR/MANIFEST.MF" <<'EOF'
Manifest-Version: 1.0
Premain-Class: io.github.octautumn.hmclpatch.HMCLRegionPatchAgent
Implementation-Title: HMCL Region Patch Agent
Implementation-Version: 1.0.0
EOF
rm -f "$AGENT_JAR"
jar cfm "$AGENT_JAR" "$BUILD_DIR/MANIFEST.MF" -C "$BUILD_DIR/shade" .
echo "构建完成：$AGENT_JAR"

if [ "$RUN_TEST" -eq 1 ]; then
    echo "== 运行自测 =="
    rm -rf "$BUILD_DIR/test-classes"
    mkdir -p "$BUILD_DIR/test-classes"
    find "$ROOT_DIR/src/test/java" -name '*.java' > "$BUILD_DIR/test-sources.txt"
    javac --release 17 -encoding UTF-8 \
        -cp "$BUILD_DIR/classes:$BUILD_DIR/deps/asm-$ASM_VERSION.jar:$BUILD_DIR/deps/asm-tree-$ASM_VERSION.jar" \
        -d "$BUILD_DIR/test-classes" @"$BUILD_DIR/test-sources.txt"
    java -cp "$BUILD_DIR/classes:$BUILD_DIR/test-classes:$BUILD_DIR/deps/asm-$ASM_VERSION.jar:$BUILD_DIR/deps/asm-tree-$ASM_VERSION.jar" \
        io.github.octautumn.hmclpatch.SelfTest
fi

if [ -n "$VERIFY_JAR" ]; then
    if [ ! -f "$VERIFY_JAR" ]; then
        echo "错误：找不到 HMCL jar：$VERIFY_JAR" >&2
        exit 1
    fi
    echo "== 用真实 HMCL jar 验证：$VERIFY_JAR =="
    # RealJarProbe 已经在上一段编译进 test-classes；如果没有 --test 也单独编译一次
    if [ ! -f "$BUILD_DIR/test-classes/io/github/octautumn/hmclpatch/RealJarProbe.class" ]; then
        rm -rf "$BUILD_DIR/test-classes"
        mkdir -p "$BUILD_DIR/test-classes"
        javac --release 17 -encoding UTF-8 -d "$BUILD_DIR/test-classes" \
            "$ROOT_DIR/src/test/java/io/github/octautumn/hmclpatch/RealJarProbe.java"
    fi
    java -javaagent:"$AGENT_JAR" -cp "$BUILD_DIR/test-classes:$VERIFY_JAR" \
        io.github.octautumn.hmclpatch.RealJarProbe
fi
