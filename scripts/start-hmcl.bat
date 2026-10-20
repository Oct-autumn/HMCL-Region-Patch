@echo off
rem ============================================================
rem  Backup launcher: use this if you don't want to change environment variables.
rem
rem  Usage:
rem    1. Put hmcl-region-patch.jar and this script into the HMCL folder.
rem    2. If HMCL.exe (official exe build) is in the same folder, double-click this script.
rem       For the jar build, put HMCL.jar in the same folder too.
rem
rem  Note: this only affects the current launch. Nothing is written to the system.
rem  This file is intentionally ASCII-only: .bat must not have a BOM and
rem  cmd.exe parses it with the current OEM code page.
rem ============================================================
setlocal
set "SCRIPT_DIR=%~dp0"

if not exist "%SCRIPT_DIR%hmcl-region-patch.jar" (
    echo [ERROR] hmcl-region-patch.jar not found. Put it in the same folder as this script.
    pause
    exit /b 1
)

if exist "%SCRIPT_DIR%HMCL.exe" (
    set "HMCL_JAVA_OPTS=-javaagent:"%SCRIPT_DIR%hmcl-region-patch.jar" -Xmx1G -XX:MinHeapFreeRatio=5 -XX:MaxHeapFreeRatio=15"
    start "" "%SCRIPT_DIR%HMCL.exe"
    exit /b 0
)

if exist "%SCRIPT_DIR%HMCL.jar" (
    rem The jar build does not read HMCL_JAVA_OPTS, pass -javaagent explicitly.
    start "" javaw -javaagent:"%SCRIPT_DIR%hmcl-region-patch.jar" -jar "%SCRIPT_DIR%HMCL.jar"
    exit /b 0
)

echo [ERROR] Neither HMCL.exe nor HMCL.jar found in this folder.
pause
exit /b 1
