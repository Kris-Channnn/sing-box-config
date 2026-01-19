@echo off
chcp 65001 >nul
title sing-box 运行器

:: 检查管理员权限
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if %errorLevel% neq 0 (
    echo 正在请求管理员权限...
    powershell Start-Process -FilePath '%0' -Verb RunAs
    exit /b
)

echo 已获得管理员权限
echo 正在切换到工作目录...

:: 切换到你的指定目录（注意路径中的空格需要用引号括起来）
cd /d "D:\APPLY\sing-box_reF1nd"

if exist "sing-box.exe" (
    echo 找到 sing-box.exe
    echo 正在启动 sing-box...
    echo ---------------------------
    sing-box.exe run -c config.json
) else (
    echo 错误：在 D:\APPLY\sing-box_reF1nd 中未找到 sing-box.exe
)

pause