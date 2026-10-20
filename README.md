# HMCL Region Patch

解除 HMCL 3.17+ 在中国大陆地区对游戏下载功能的限制（针对 [HMCL PR #7017](https://github.com/HMCL-dev/HMCL/pull/7017)）。

> ⚠️ 仅限个人在自己机器上使用。本补丁不修改 HMCL 的任何文件，只在 JVM 内存里改写一个区域判断类的字节码。
> 绕过地区限制存在合规风险，请自行判断并承担。

## 它是怎么工作的

PR #7017 在 `org.jackhuang.hmcl.util.RegionUtils` 里新增了这个字段：

```java
private static final boolean IS_CHINA_MAINLAND_MACHINE = checkMachineIsChinaMainland();
```

它通过时区、语言、Windows 地理区域（GetUserGeoID）判断机器是否在中国大陆，再通过 `ipwho.is` 判断网络出口。
判定为大陆后，下载页会被禁用并显示提示。

本注入包是一个 Java agent：在 HMCL 启动的 `premain` 阶段注册 `ClassFileTransformer`，
等 `RegionUtils` 类被加载时把字节码改成让判断恒为 `false`。三种策略依次尝试：

1. 把 `checkMachineIsChinaMainland()` 方法体改成 `return false`（覆盖所有调用点）；
2. 在 `<clinit>` 中每条 `putstatic IS_CHINA_MAINLAND_MACHINE` 之后补一次 `false` 赋值（只依赖字段名，兜底 HMCL 后续改名）；
3. 把两个公开判断方法 `isIsChinaMainlandMachine()` / `isIsChinaMainlandNetwork()` 改成 `return false`。

全部不命中时只写一条 WARN 日志，保持 HMCL 原行为，不会导致启动失败。

因为 `isIsChinaMainlandNetwork()` 的第一行就是 `if (!IS_CHINA_MAINLAND_MACHINE) return false`，
所以字段变成 `false` 后连 `ipwho.is` 网络请求都不会发。

**不改 HMCL 的 jar/exe 文件**，所以 HMCL 的签名完整性校验、自动更新、微软正版登录都不受影响。

## 构建

需要 **JDK 17+**（`java` / `javac` / `jar` 在 PATH 里），首次构建会从 Maven Central 下载 ASM 9.9（约 180KB，缓存在 `build/deps/`）。

Windows：

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1 -Test
```

Linux / macOS / WSL：

```bash
./build.sh --test
```

产物是 `dist/hmcl-region-patch.jar`。

用真实 HMCL jar 做端到端验证（可选，推荐在升级 HMCL 后跑一次）：

```bash
./build.sh --verify /path/to/HMCL-3.17.0.362.jar
# 或
powershell -ExecutionPolicy Bypass -File .\build.ps1 -Verify .\HMCL-3.17.0.362.jar
```

## 安装

### Windows（官方 exe，推荐）

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-windows.ps1
```

脚本会把 `-javaagent:...\hmcl-region-patch.jar` 写进当前用户的 `HMCL_JAVA_OPTS` 环境变量
（HMCL 官方启动器 HMCLauncher.exe 会读取它），然后完全关闭 HMCL 再重新双击启动即可。
重复执行是安全的（幂等），旧参数会被替换。

如果重启 HMCL 后没生效，注销并重新登录 Windows 一次（让资源管理器刷新环境变量）。

**项目在 WSL 里构建、HMCL 在 Windows 上运行？** 先把 `dist/hmcl-region-patch.jar` 复制到 Windows 本地磁盘（例如 `D:\tools\`），再显式指定路径安装：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-windows.ps1 -JarPath D:\tools\hmcl-region-patch.jar
```

不要把 `\\wsl$\...` 这类 UNC 路径直接写进 `HMCL_JAVA_OPTS`，官方启动器的命令行解析对 UNC 路径不稳定。

**不想改环境变量**：把 `dist/hmcl-region-patch.jar` 和 `scripts/start-hmcl.bat` 复制到 HMCL 所在目录，双击 `start-hmcl.bat` 启动。同目录有 `HMCL.exe` 时走 exe；只有 `HMCL.jar` 时按 jar 版启动。

### Linux / macOS

```bash
./scripts/install-linux.sh          # 写入 ~/.bashrc
./scripts/install-linux.sh --print  # 只打印配置，手动粘贴
./scripts/install-linux.sh --rc ~/.zshrc
```

或者不碰 shell 配置，用包装脚本启动：

```bash
./scripts/hmcl-patched.sh /path/to/HMCL.sh
```

注意官方 `HMCL.sh` 展开 `HMCL_JAVA_OPTS` 时不处理引号，路径不能带空格；安装脚本会自动把 jar 复制到 `~/.local/share/hmcl-region-patch/` 规避。

### 手动方式（任何平台）

```bash
# 官方 exe / sh
set HMCL_JAVA_OPTS=-javaagent:D:\path\hmcl-region-patch.jar -Xmx1G -XX:MinHeapFreeRatio=5 -XX:MaxHeapFreeRatio=15   # Windows
export HMCL_JAVA_OPTS="-javaagent:$HOME/path/hmcl-region-patch.jar -XX:MinHeapFreeRatio=5 -XX:MaxHeapFreeRatio=15"  # Linux/macOS

# jar 版
java -javaagent:/path/hmcl-region-patch.jar -jar HMCL.jar
```

> 设置 `HMCL_JAVA_OPTS` 会**替换**启动器原本的默认 JVM 参数，所以上面把默认内存参数一起写上了，
> 避免 HMCL 内存配置被重置。

## 验证是否生效

看注入包同目录的 `hmcl-region-patch.log`，出现类似内容即成功：

```
[2026-10-20 18:00:00.000] [INFO] HMCL Region Patch 已注入（Java 17.0.20.1，参数：无）
[2026-10-20 18:00:00.000] [INFO] ClassFileTransformer 已注册，等待 RegionUtils 类加载
[2026-10-20 18:00:03.123] [INFO] 注入成功：策略 1（checkMachineIsChinaMainland() -> false）
```

如果看到 `未命中任何注入策略`，说明 HMCL 版本结构变了，需要更新本补丁（见下方兼容性说明）。

## 卸载

Windows：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\uninstall-windows.ps1
```

Linux / macOS：

```bash
./scripts/uninstall-linux.sh
```

## 已知副作用

1. **HMCL 自动更新后重启会丢参数。** HMCL 的更新重启（`UpdateHandler.startJava`）只转发 `-D` / `-X` 参数，不转发 `-javaagent`，所以更新后的那一轮运行补丁不生效——手动关掉 HMCL 再重新打开一次即可。
2. **下载源默认变了。** 判断变为非大陆后，HMCL 默认优先官方源（原来是 BMCLAPI 镜像优先），大陆网络下可能下载慢，可以在 HMCL「设置 → 下载 → 下载源」里改成镜像。
3. **Terracotta 页面会多一条提示**（"多人联机功能目前仅为中国内地用户提供服务"），只是 UI 提示，不影响游戏下载。
4. **导出/同步设置无影响**，补丁不写 HMCL 配置。

## 兼容性

- 已在 HMCL nightly 3.17.0.362（含 PR #7017）上验证：JDK 17 与 JDK 25 下，字段、两个判断方法全部变为 `false`。
- 如果 HMCL 后续重构 `RegionUtils`（改名、把字段改成编译期常量并内联等），注入可能失效；届时日志会提示，需要按新结构更新策略。
- 自测覆盖了三种字节码结构和两种兜底场景，见 `src/test/java/io/github/octautumn/hmclpatch/SelfTest.java`。

## 目录结构

```
.
├── build.sh / build.ps1        构建脚本（含 --test / --verify）
├── dist/                       构建产物 hmcl-region-patch.jar
├── src/main/java/...           agent 主代码
│   ├── HMCLRegionPatchAgent.java     premain 入口
│   ├── RegionUtilsTransformer.java   字节码改写（三级策略）
│   └── PatchLogger.java              日志（stderr + 文件）
├── src/test/java/...           自测 SelfTest + 真实 jar 验证 RealJarProbe
└── scripts/
    ├── install-windows.ps1 / uninstall-windows.ps1
    ├── start-hmcl.bat          备份启动方式（Windows）
    ├── install-linux.sh / uninstall-linux.sh
    └── hmcl-patched.sh         Linux 包装启动脚本
```

## 依赖与许可

- 依赖 [OW2 ASM](https://asm.ow2.io/)（BSD-3-Clause），已 shade 进产物。
- 本仓库不包含 HMCL 的任何代码，也未修改 HMCL 的发布文件。
