@echo off
:: ---------------------------------------------------
:: 自动提权模块 (检测是否有管理员权限，没有则请求)
:: ---------------------------------------------------
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"

if '%errorlevel%' NEQ '0' (
    echo 正在请求管理员权限...
    goto UACPrompt
) else ( goto gotAdmin )

:UACPrompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "%~s0", "", "", "runas", 1 >> "%temp%\getadmin.vbs"
    "%temp%\getadmin.vbs"
    exit /B

:gotAdmin
    if exist "%temp%\getadmin.vbs" ( del "%temp%\getadmin.vbs" )
    :: 提权后，系统目录会变，必须切换回脚本所在目录
    cd /d "D:\APPLY\sing-box_reF1nd"

:: ---------------------------------------------------
:: 主逻辑区域
:: ---------------------------------------------------

echo 已获取管理员权限
:: 启动 PowerShell 脚本
powershell -NoProfile -ExecutionPolicy Bypass -File "singbox-manager.ps1"

pause