<#
.SYNOPSIS
    为 Windows 上的官方 HMCL.exe 安装区域补丁。

.DESCRIPTION
    把 -javaagent 参数写入当前用户的 HMCL_JAVA_OPTS 环境变量。
    HMCL 官方启动器（HMCLauncher.exe）会读取这个变量并传给 JVM，
    因此双击 HMCL.exe 即可生效，不需要改 HMCL 本身。

    重复运行是安全的：会先移除旧版本注入包留下的参数再重新添加。
    卸载请运行 uninstall-windows.ps1。

.PARAMETER JarPath
    注入包路径；默认自动找 ..\dist\hmcl-region-patch.jar 或脚本同目录的 jar。

.PARAMETER MaxHeap
    首次安装时写入的 -Xmx 值；默认 -Xmx1G（与 HMCLauncher 默认值一致）。
    如果用户已有自定义的 HMCL_JAVA_OPTS，则保留原有参数不动。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\install-windows.ps1
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$JarPath = "",
    [string]$MaxHeap = "-Xmx1G"
)

$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot
$RootDir = Split-Path -Parent $ScriptDir

if ([string]::IsNullOrWhiteSpace($JarPath)) {
    $candidates = @(
        (Join-Path $RootDir "dist\hmcl-region-patch.jar"),
        (Join-Path $ScriptDir "hmcl-region-patch.jar")
    )
    $JarPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if ([string]::IsNullOrWhiteSpace($JarPath) -or -not (Test-Path -LiteralPath $JarPath)) {
    throw "找不到注入包。请先运行 build.ps1 构建，或用 -JarPath 指定 hmcl-region-patch.jar 的路径。"
}
$JarPath = (Resolve-Path -LiteralPath $JarPath).Path
if ($JarPath.StartsWith("\\")) {
    Write-Warning "检测到 UNC 路径（$JarPath）。建议先把 jar 复制到 Windows 本地磁盘再安装，避免启动器解析 UNC 路径出问题。"
}

# 读取现有的用户级 HMCL_JAVA_OPTS，并移除本注入包之前的参数（保证幂等）
$current = [Environment]::GetEnvironmentVariable("HMCL_JAVA_OPTS", "User")
if ($null -eq $current) { $current = "" }
$pattern = '-javaagent:("[^"]*hmcl-region-patch\.jar"|\S*hmcl-region-patch\.jar)'
$remaining = [regex]::Replace($current, $pattern, " ").Trim()
$remaining = (($remaining -split '\s+') | Where-Object { $_ }) -join ' '

# 如果原本没有 HMCL_JAVA_OPTS（或清理后为空），补上与 HMCLauncher 一致的默认 JVM 参数
if ([string]::IsNullOrWhiteSpace($remaining)) {
    $remaining = "$MaxHeap -XX:MinHeapFreeRatio=5 -XX:MaxHeapFreeRatio=15"
}

$newValue = "$remaining -javaagent:`"$JarPath`""
[Environment]::SetEnvironmentVariable("HMCL_JAVA_OPTS", $newValue, "User")

Write-Host ""
Write-Host "已写入用户环境变量 HMCL_JAVA_OPTS：" -ForegroundColor Green
Write-Host "  $newValue"
Write-Host ""
Write-Host "接下来："
Write-Host "  1. 完全关闭已有的 HMCL 进程，重新双击 HMCL.exe 启动。"
Write-Host "  2. 如果 HMCL 是从资源管理器启动且没有生效，注销后重新登录一次（环境变量刷新）。"
Write-Host "  3. 日志在注入包同目录的 hmcl-region-patch.log。"
Write-Host ""
Write-Host "卸载：powershell -ExecutionPolicy Bypass -File .\scripts\uninstall-windows.ps1"
