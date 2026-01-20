batch
@echo off
chcp 65001 >nul
title sing-box 管理工具 (管理员模式)
color 0A

echo ==========================================
echo        sing-box Windows 管理脚本
echo ==========================================
echo.
echo 配置文件: D:\APPLY\sing-box_reF1nd\config.json
echo.
echo 需要管理员权限运行...
echo.

REM 检查是否已管理员运行
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo 正在请求管理员权限...
    echo.
    powershell -Command "Start-Process PowerShell -Verb RunAs -ArgumentList '-NoExit -ExecutionPolicy Bypass -File \"D:\APPLY\sing-box_reF1nd\singbox-manager.ps1"'"
) else (
    echo 已经是管理员权限，正在启动脚本...
    echo.
    powershell -ExecutionPolicy Bypass -File "D:\APPLY\sing-box_reF1nd\singbox-manager.ps1"
)


pause
