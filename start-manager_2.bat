@echo off
setlocal EnableDelayedExpansion

:: ===================================================
:: 1. 自动提权模块
:: ===================================================
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"

if '%errorlevel%' NEQ '0' (
    goto UACPrompt
) else ( goto gotAdmin )

:UACPrompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "%~s0", "", "", "runas", 1 >> "%temp%\getadmin.vbs"
    "%temp%\getadmin.vbs"
    exit /B

:gotAdmin
    if exist "%temp%\getadmin.vbs" ( del "%temp%\getadmin.vbs" )
    :: 切换到脚本所在目录
    cd /d "sing-box.exe和config.json所在目录"

:: ===================================================
:: 2. 启动逻辑 (大窗口修复版)
:: ===================================================

:: 检查脚本是否存在
if not exist "singbox-manager.ps1" (
    echo [ERROR] 未找到 singbox-manager.ps1
    echo 请确保 .bat 和 .ps1 文件在同一个文件夹内。
    pause
    exit
)

:: 检测 Windows Terminal
where wt.exe >nul 2>nul
if %errorlevel% equ 0 (
    :: ---------------------------------------------------
    :: 修复说明：
    :: --size 140,45 必须紧跟在 wt.exe 后面，作为全局参数
    :: ---------------------------------------------------
    
    start "" "wt.exe" --size 110,40 -w 0 nt -d . --title "Sing-box Manager" powershell -NoProfile -ExecutionPolicy Bypass -File "singbox-manager.ps1"
    
    exit
) else (
    echo [INFO] 未检测到 Windows Terminal，使用默认控制台。
    
    :: 降级方案：强制拉大 CMD 窗口
    mode con: cols=110 lines=40
    powershell -NoProfile -ExecutionPolicy Bypass -File "singbox-manager.ps1"
    pause

)
