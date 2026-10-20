@echo off
chcp 65001 >nul
rem ============================================================
rem  备份启动方式：不想修改环境变量时使用本脚本
rem
rem  用法：
rem    1. 把 hmcl-region-patch.jar 和本脚本放到 HMCL 所在目录；
rem    2. 同目录有 HMCL.exe（官方 exe 版）时，双击本脚本即可；
rem       只有 HMCL.jar（jar 版）时，把 HMCL.jar 也放同目录再双击。
rem
rem  注意：本脚本只影响这一次启动，不写任何环境变量。
rem ============================================================
setlocal
set "SCRIPT_DIR=%~dp0"

if not exist "%SCRIPT_DIR%hmcl-region-patch.jar" (
    echo [错误] 找不到 hmcl-region-patch.jar，请和本脚本放在同一目录。
    pause
    exit /b 1
)

if exist "%SCRIPT_DIR%HMCL.exe" (
    set "HMCL_JAVA_OPTS=-javaagent:"%SCRIPT_DIR%hmcl-region-patch.jar" -Xmx1G -XX:MinHeapFreeRatio=5 -XX:MaxHeapFreeRatio=15"
    start "" "%SCRIPT_DIR%HMCL.exe"
    exit /b 0
)

if exist "%SCRIPT_DIR%HMCL.jar" (
    rem jar 版不会读取 HMCL_JAVA_OPTS，需要显式把 -javaagent 传给 java
    start "" javaw -javaagent:"%SCRIPT_DIR%hmcl-region-patch.jar" -jar "%SCRIPT_DIR%HMCL.jar"
    exit /b 0
)

echo [错误] 同目录既没有 HMCL.exe 也没有 HMCL.jar。
pause
exit /b 1
