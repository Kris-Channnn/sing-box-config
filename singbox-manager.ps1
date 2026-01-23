<#
.SYNOPSIS
    Sing-box 管理脚本 (停止并退出版)
.DESCRIPTION
    修改了退出逻辑：0 为彻底停止程序并退出，Q 为仅关闭窗口(保留后台运行)。
#>

# --- 配置区域 ---
$ExeName = "sing-box"
$ExePath = ".\sing-box.exe"
$ConfigPath = "config.json"
$LogFile = ".\sing-box.log"            # 标准运行日志
$ErrorLogFile = ".\sing-box_error.log" # 错误日志
# ----------------

$ScriptDir = $PSScriptRoot
if ($ScriptDir) { Set-Location $ScriptDir }

# --- 核心辅助函数：带退出键的日志查看器 ---
function Watch-LogFile {
    param (
        [string]$FilePath,
        [string]$Title
    )

    if (-not (Test-Path $FilePath)) {
        Write-Warning "文件不存在: $FilePath"
        return
    }

    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "    $Title" -ForegroundColor Yellow
    Write-Host "    [按 'Q' 或 'Esc' 键返回菜单]" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Cyan

    Get-Content $FilePath -Tail 15

    $stream = [System.IO.File]::Open($FilePath, 'Open', 'Read', 'ReadWrite')
    $reader = New-Object System.IO.StreamReader($stream)
    $reader.BaseStream.Seek(0, [System.IO.SeekOrigin]::End) | Out-Null

    try {
        while ($true) {
            $line = $reader.ReadLine()
            if ($line -ne $null) {
                Write-Host $line
            } else {
                Start-Sleep -Milliseconds 100
            }

            if ([System.Console]::KeyAvailable) {
                $key = [System.Console]::ReadKey($true)
                if ($key.Key -eq 'Q' -or $key.Key -eq 'Escape') {
                    Write-Host "`n[正在返回菜单...]" -ForegroundColor Yellow
                    break
                }
            }
        }
    } finally {
        $reader.Close()
        $stream.Close()
    }
}

# --- 功能函数 ---

function Check-Admin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning "建议以管理员权限运行。"
        return $false
    }
    return $true
}

function Show-Header {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "       Sing-box 管理脚本 v0.6" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Cyan
}

function Show-Menu {
    Show-Header
    Write-Host " 1. 启动 (Start) [后台模式]" -ForegroundColor Green
    Write-Host " 2. 停止 (Stop)" -ForegroundColor Red
    Write-Host " 3. 重启 (Restart)" -ForegroundColor Yellow
    Write-Host " 4. 查看状态 (Status)" -ForegroundColor Cyan
    Write-Host "------------------------------------------" -ForegroundColor DarkGray
    Write-Host " 5. 查看标准日志 (Info Log)" -ForegroundColor Green
    Write-Host " 6. 查看错误日志 (Error Log)" -ForegroundColor Red
    Write-Host "------------------------------------------" -ForegroundColor DarkGray
    Write-Host " 7. 检查配置文件" -ForegroundColor Gray
    Write-Host " 8. 设置开机自启" -ForegroundColor Magenta
    Write-Host " 9. 取消开机自启" -ForegroundColor DarkMagenta
    Write-Host "------------------------------------------" -ForegroundColor DarkGray
    # 这里是修改的重点
    Write-Host " 0. 停止服务并退出 (Kill & Exit)" -ForegroundColor Red
    Write-Host " Q. 仅退出脚本 (Keep Running)" -ForegroundColor Gray
    Write-Host "==========================================" -ForegroundColor Cyan
}

function Start-App {
    if (Get-Process -Name $ExeName -ErrorAction SilentlyContinue) {
        Write-Warning "Sing-box 已经在运行中。"
        return
    }
    if (-not (Test-Path $ExePath)) { Write-Error "未找到 $ExePath"; return }

    Write-Host "正在后台启动 $ExeName ..." -NoNewline
    
    try {
        Start-Process -FilePath $ExePath `
                      -ArgumentList "run -c $ConfigPath" `
                      -WindowStyle Hidden `
                      -RedirectStandardOutput $LogFile `
                      -RedirectStandardError $ErrorLogFile `
                      -ErrorAction Stop
        
        Start-Sleep -Seconds 2
        
        if (Get-Process -Name $ExeName -ErrorAction SilentlyContinue) {
            Write-Host " [成功]" -ForegroundColor Green
        } else {
            Write-Host " [失败]" -ForegroundColor Red
            Write-Host "检测到启动失败，正在打开错误日志..." -ForegroundColor Yellow
            Start-Sleep -Seconds 1
            View-ErrorLog
        }
    } catch { Write-Error $_ }
}

function Stop-App {
    $proc = Get-Process -Name $ExeName -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Host "正在停止 Sing-box ..." -NoNewline
        Stop-Process -Name $ExeName -Force
        Write-Host " [已停止]" -ForegroundColor Red
    } else { Write-Warning "Sing-box 未运行" }
}

function Restart-App { Stop-App; Start-Sleep -Seconds 1; Start-App }

function Get-Status {
    $proc = Get-Process -Name $ExeName -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Host "✅ 运行中 | PID: $($proc.Id) | 内存: $([math]::Round($proc.WorkingSet64 / 1MB, 2)) MB" -ForegroundColor Green
        $ports = @(2080, 1080, 7890)
        foreach ($p in $ports) {
            if (Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue) {
                Write-Host "   -> 端口 $p 正在监听" -ForegroundColor Cyan
            }
        }
    } else { Write-Host "❌ 未运行" -ForegroundColor Red }
}

function View-Log {
    if (Test-Path $LogFile) {
        Watch-LogFile -FilePath $LogFile -Title "正在查看标准日志 (Info)"
    } else {
        Write-Warning "日志文件不存在 (程序可能未运行)"
    }
}

function View-ErrorLog {
    if (Test-Path $ErrorLogFile) {
        Watch-LogFile -FilePath $ErrorLogFile -Title "正在查看错误日志 (Error)"
    } else {
        Write-Warning "错误日志文件不存在"
    }
}

function Test-Config {
    Write-Host "检查配置..."
    Start-Process -FilePath $ExePath -ArgumentList "check -c $ConfigPath" -NoNewWindow -Wait
}

function Install-Task {
    if (-not (Check-Admin)) { return }
    $Action = New-ScheduledTaskAction -Execute (Convert-Path $ExePath) -Argument "run -c `"$((Convert-Path $ConfigPath))`"" -WorkingDirectory $ScriptDir
    Register-ScheduledTask -TaskName "SingBox_AutoStart" -Action $Action -Trigger (New-ScheduledTaskTrigger -AtLogOn) -Principal (New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest) -Force | Out-Null
    Write-Host "已设置开机自启。" -ForegroundColor Green
}

function Uninstall-Task {
    if (-not (Check-Admin)) { return }
    Unregister-ScheduledTask -TaskName "SingBox_AutoStart" -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "已取消开机自启。" -ForegroundColor Green
}

# --- 主循环 ---
if (-not (Check-Admin)) { Start-Sleep -Seconds 1 }

while ($true) {
    Show-Menu
    $selection = Read-Host "请输入选项"
    switch ($selection) {
        "1" { Start-App; Pause }
        "2" { Stop-App; Pause }
        "3" { Restart-App; Pause }
        "4" { Get-Status; Pause }
        "5" { View-Log }
        "6" { View-ErrorLog }
        "7" { Test-Config; Pause }
        "8" { Install-Task; Pause }
        "9" { Uninstall-Task; Pause }
        
        # 修改点：选择 0 会先停止 sing-box 再退出
        "0" { 
            Stop-App
            Write-Host "程序已停止，脚本正在退出..." -ForegroundColor Gray
            Start-Sleep -Seconds 1
            exit 
        }
        
        # 新增点：选择 Q 仅退出脚本窗口，保留 sing-box 运行
        "Q" { exit }
        "q" { exit }

        Default { Write-Warning "无效选项"; Start-Sleep -Seconds 1 }
    }
}