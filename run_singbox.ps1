# 请求管理员权限
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "正在请求管理员权限..." -ForegroundColor Yellow
    Start-Process PowerShell -Verb RunAs "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

# 设置控制台编码为UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 切换到指定目录
$workingDir = "D:\APPLY\sing-box_reF1nd"
Write-Host "切换到工作目录: $workingDir" -ForegroundColor Green
Set-Location -Path $workingDir

# 检查文件是否存在
if (Test-Path "sing-box.exe") {
    Write-Host "找到 sing-box.exe，正在启动..." -ForegroundColor Green
    Write-Host "--------------------------------" -ForegroundColor Cyan
    
    # 运行命令
    .\sing-box.exe run -c config.json
    
    # 如果程序退出，暂停以便查看输出
    Write-Host "`nsing-box 已退出" -ForegroundColor Yellow
    pause
} else {
    Write-Host "错误：在当前目录未找到 sing-box.exe" -ForegroundColor Red
    Write-Host "当前目录: $(Get-Location)" -ForegroundColor Yellow
    pause
}