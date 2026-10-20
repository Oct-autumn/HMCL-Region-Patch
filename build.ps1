<#
.SYNOPSIS
    HMCL Region Patch 构建脚本（Windows PowerShell 5.1+）。

.DESCRIPTION
    依赖 JDK 17+（java / javac / jar 在 PATH 中）。
    首次构建会从 Maven Central 下载 ASM 并缓存在 build\deps\。

    注意：PowerShell 5.1 中原生命令（java.exe 等）往 stderr 写内容会被包装成
    NativeCommandError；在 $ErrorActionPreference = "Stop" 下会直接终止脚本。
    java -version、javac 的警告、我们自己的 agent 日志都走 stderr，所以本脚本
    统一用 Continue 模式，原生命令的 stderr 通过 2>&1 | ForEach-Object 收进管道，
    成功与否一律看 $LASTEXITCODE。

.PARAMETER Test
    构建后运行自测程序（SelfTest）。

.PARAMETER Verify
    构建后用指定的真实 HMCL jar 做端到端验证（例如 HMCL-3.17.0.xxx.jar）。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\build.ps1 -Test

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\build.ps1 -Verify .\HMCL.jar
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Test,
    [string]$Verify = ""
)

# 原生命令会把正常信息写到 stderr（java -version 就是经典例子），Stop 模式会误杀脚本
$ErrorActionPreference = "Continue"
$RootDir = $PSScriptRoot
$BuildDir = Join-Path $RootDir "build"
$DistDir = Join-Path $RootDir "dist"
$AsmVersion = if ($env:ASM_VERSION) { $env:ASM_VERSION } else { "9.9" }
$AsmRepo = if ($env:ASM_REPO) { $env:ASM_REPO } else { "https://repo1.maven.org/maven2" }
$AgentJar = Join-Path $DistDir "hmcl-region-patch.jar"

function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "找不到 $Name，请安装 JDK 17+ 并加入 PATH"
    }
}

function Get-AsmJar([string]$Name) {
    $target = Join-Path $BuildDir "deps\$Name-$AsmVersion.jar"
    if (Test-Path -LiteralPath $target) {
        return $target
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    $url = "$AsmRepo/org/ow2/asm/$Name/$AsmVersion/$Name-$AsmVersion.jar"
    Write-Host "下载 $Name $AsmVersion ..."
    try {
        Invoke-WebRequest -Uri $url -OutFile $target -UseBasicParsing -ErrorAction Stop
    } catch {
        throw "下载 $Name 失败：$($_.Exception.Message)。可设置 ASM_REPO 环境变量换镜像。"
    }
    if (-not (Test-Path -LiteralPath $target)) {
        throw "下载 $Name 失败：$target 不存在"
    }
    return $target
}

Require-Command java
Require-Command javac
Require-Command jar

# 检查 javac 版本不低于 17。
# 用 javac -version（输出到 stdout）而不是 java -version（输出到 stderr，PS 5.1 会误判为错误）。
$javacVersionOutput = (& javac -version 2>&1 | Out-String).Trim()
if ($javacVersionOutput -match 'javac (\d+)') {
    $javaMajor = [int]$Matches[1]
    if ($javaMajor -lt 17) {
        throw "需要 JDK 17+，当前 javac 版本输出：$javacVersionOutput"
    }
    Write-Host "使用 javac 版本：$javacVersionOutput"
} else {
    throw "无法识别 javac 版本：$javacVersionOutput"
}

$asmJar = Get-AsmJar "asm"
$asmTreeJar = Get-AsmJar "asm-tree"

Write-Host "== 编译主代码 =="
$classesDir = Join-Path $BuildDir "classes"
if (Test-Path $classesDir) { Remove-Item -Recurse -Force $classesDir }
New-Item -ItemType Directory -Force -Path $classesDir | Out-Null
$mainSources = Get-ChildItem -Path (Join-Path $RootDir "src\main\java") -Recurse -Filter *.java | ForEach-Object { $_.FullName }
if (-not $mainSources) { throw "src\main\java 下没有找到 Java 源文件" }
$sourcesFile = Join-Path $BuildDir "sources.txt"
# 用 ASCII 写参数文件：PowerShell 5.1 的 UTF8 会带 BOM，javac 的 @argfile 可能无法解析
$mainSources | Set-Content -Path $sourcesFile -Encoding ASCII
& javac --release 17 -encoding UTF-8 -cp "$asmJar;$asmTreeJar" -d $classesDir "@$sourcesFile" 2>&1 | ForEach-Object { Write-Host $_ }
if ($LASTEXITCODE -ne 0) { throw "主代码编译失败（javac 退出码 $LASTEXITCODE）" }

Write-Host "== 合并 ASM 依赖 =="
$shadeDir = Join-Path $BuildDir "shade"
if (Test-Path $shadeDir) { Remove-Item -Recurse -Force $shadeDir }
New-Item -ItemType Directory -Force -Path $shadeDir | Out-Null
Push-Location $shadeDir
try {
    & jar xf $asmJar 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw "解压 asm 失败" }
    & jar xf $asmTreeJar 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw "解压 asm-tree 失败" }
} finally {
    Pop-Location
}
Remove-Item -Recurse -Force (Join-Path $shadeDir "module-info.class") -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force (Join-Path $shadeDir "META-INF") -ErrorAction SilentlyContinue
Copy-Item -Recurse -Force (Join-Path $classesDir "*") $shadeDir

Write-Host "== 生成注入包 =="
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
$manifestPath = Join-Path $BuildDir "MANIFEST.MF"
@(
    "Manifest-Version: 1.0"
    "Premain-Class: io.github.octautumn.hmclpatch.HMCLRegionPatchAgent"
    "Implementation-Title: HMCL Region Patch Agent"
    "Implementation-Version: 1.0.0"
) | Set-Content -Path $manifestPath -Encoding ASCII
if (Test-Path $AgentJar) { Remove-Item -Force $AgentJar }
& jar cfm $AgentJar $manifestPath -C $shadeDir . 2>&1 | ForEach-Object { Write-Host $_ }
if ($LASTEXITCODE -ne 0) { throw "打包失败（jar 退出码 $LASTEXITCODE）" }
Write-Host "构建完成：$AgentJar"

if ($Test) {
    Write-Host "== 运行自测 =="
    $testClassesDir = Join-Path $BuildDir "test-classes"
    if (Test-Path $testClassesDir) { Remove-Item -Recurse -Force $testClassesDir }
    New-Item -ItemType Directory -Force -Path $testClassesDir | Out-Null
    $testSources = Get-ChildItem -Path (Join-Path $RootDir "src\test\java") -Recurse -Filter *.java | ForEach-Object { $_.FullName }
    $testSourcesFile = Join-Path $BuildDir "test-sources.txt"
    $testSources | Set-Content -Path $testSourcesFile -Encoding ASCII
    & javac --release 17 -encoding UTF-8 -cp "$classesDir;$asmJar;$asmTreeJar" -d $testClassesDir "@$testSourcesFile" 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw "测试代码编译失败（javac 退出码 $LASTEXITCODE）" }
    & java -cp "$classesDir;$testClassesDir;$asmJar;$asmTreeJar" io.github.octautumn.hmclpatch.SelfTest 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw "自测失败（退出码 $LASTEXITCODE）" }
}

if ($Verify) {
    if (-not (Test-Path -LiteralPath $Verify)) {
        throw "找不到 HMCL jar：$Verify"
    }
    Write-Host "== 用真实 HMCL jar 验证：$Verify =="
    $testClassesDir = Join-Path $BuildDir "test-classes"
    if (-not (Test-Path (Join-Path $testClassesDir "io\github\octautumn\hmclpatch\RealJarProbe.class"))) {
        if (Test-Path $testClassesDir) { Remove-Item -Recurse -Force $testClassesDir }
        New-Item -ItemType Directory -Force -Path $testClassesDir | Out-Null
        & javac --release 17 -encoding UTF-8 -d $testClassesDir (Join-Path $RootDir "src\test\java\io\github\octautumn\hmclpatch\RealJarProbe.java") 2>&1 | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) { throw "验证探针编译失败" }
    }
    & java "-javaagent:$AgentJar" -cp "$testClassesDir;$Verify" io.github.octautumn.hmclpatch.RealJarProbe 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw "端到端验证失败（退出码 $LASTEXITCODE）" }
}
