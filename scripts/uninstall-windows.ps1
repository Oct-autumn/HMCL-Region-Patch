<#
.SYNOPSIS
    卸载 Windows 上的 HMCL 区域补丁。

.DESCRIPTION
    从当前用户的 HMCL_JAVA_OPTS 环境变量中移除注入包参数，
    保留用户自定义的其它 JVM 参数。如果移除后不剩任何参数，则删除该环境变量。
#>
#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$current = [Environment]::GetEnvironmentVariable("HMCL_JAVA_OPTS", "User")
if ($null -eq $current -or [string]::IsNullOrWhiteSpace($current)) {
    Write-Host "HMCL_JAVA_OPTS 未设置，无需卸载。"
    exit 0
}

$pattern = '-javaagent:("[^"]*hmcl-region-patch\.jar"|\S*hmcl-region-patch\.jar)'
$remaining = [regex]::Replace($current, $pattern, " ").Trim()
$remaining = (($remaining -split '\s+') | Where-Object { $_ }) -join ' '

if ([string]::IsNullOrWhiteSpace($remaining)) {
    [Environment]::SetEnvironmentVariable("HMCL_JAVA_OPTS", $null, "User")
    Write-Host "已删除 HMCL_JAVA_OPTS（原本只包含注入参数）。" -ForegroundColor Green
} else {
    [Environment]::SetEnvironmentVariable("HMCL_JAVA_OPTS", $remaining, "User")
    Write-Host "已移除注入参数，保留其它参数：" -ForegroundColor Green
    Write-Host "  $remaining"
}
Write-Host "重新启动 HMCL 后生效。"
