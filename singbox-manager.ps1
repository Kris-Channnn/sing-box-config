<#
.SYNOPSIS
    Sing-box 管理脚本 (UI 美化版)
.DESCRIPTION
    1. 界面升级：ASCII 艺术标题、清晰的分区、图标装饰。
    2. 核心逻辑：保留上个版本的严格日志检查(启动时触发)、3份备份、配置检查完善。
    3. 监控模式：保留精简版实时监控。
#>

# --- 配置区域 ---
$ExeName = "sing-box"
$ExePath = ".\sing-box.exe"
$ConfigPath = "config.json"
$LogFile = ".\sing-box.log"            # 标准运行日志
$ErrorLogFile = ".\sing-box_error.log" # 功能日志
$MaxLogSizeBytes = 1024 * 1024         # 日志上限 1024KB (1MB)
$MaxBackups = 3                        # 保留备份数量
# ----------------

$ScriptDir = $PSScriptRoot
if ($ScriptDir) { Set-Location $ScriptDir }
$TitleArt = @"
   _____ _             _                 
  / ____(_)           | |                
 | (___  _ _ __   __ _| |__   _____  __  
  \___ \| | '_ \ / _` | '_ \ / _ \ \/ /  
  ____) | | | | | (_| | |_) | (_) >  <   
 |_____/|_|_| |_|\__, |_.__/ \___/_/\_\  
                  __/ |   Manager v2.0   
                 |___/                   
"@

# --- 辅助 UI 函数 ---
function Draw-Title {
    Clear-Host
    Write-Host $TitleArt -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor DarkGray
}

function Write-Line {
    param ([string]$Text, [ConsoleColor]$Color = "White")
    Write-Host "  $Text" -ForegroundColor $Color
}

function Check-Admin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning "⚠ 为了获得最佳体验，请以管理员身份运行此脚本。"
        Start-Sleep -Seconds 2
        return $false
    }
    return $true
}

# --- 核心逻辑 ---

# 日志轮转 (启动时触发)
function Check-LogSize {
    param ([string]$FilePath)
    if (-not (Test-Path $FilePath)) { return }
    try {
        $fileItem = Get-Item $FilePath
        if ($fileItem.Length -gt $MaxLogSizeBytes) {
            Write-Host "  ⚡ 日志 [ $($fileItem.Name) ] 超过 1MB，正在执行轮转..." -ForegroundColor Yellow
            $limit = $MaxBackups
            while (Test-Path "$FilePath.$limit") { Remove-Item "$FilePath.$limit" -Force -ErrorAction SilentlyContinue; $limit++ }
            if (Test-Path "$FilePath.$MaxBackups") { Remove-Item "$FilePath.$MaxBackups" -Force -ErrorAction SilentlyContinue }
            for ($i = $MaxBackups - 1; $i -ge 1; $i--) {
                $next = $i + 1
                if (Test-Path "$FilePath.$i") { Move-Item "$FilePath.$i" "$FilePath.$next" -Force -ErrorAction SilentlyContinue }
            }
            Move-Item $FilePath "$FilePath.1" -Force -ErrorAction SilentlyContinue
            Write-Host "  ✅ 轮转完成，旧日志已归档。" -ForegroundColor DarkGray
        }
    } catch { Write-Warning "  ❌ 日志轮转失败 (文件可能被占用)" }
}

# 监控日志 (仅查看，不自动切割)
function Watch-LogFile {
    param ([string]$FilePath, [string]$Title)
    if (-not (Test-Path $FilePath)) { Write-Warning "  ❌ 文件不存在: $FilePath"; return }

    Clear-Host
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "  📄 $Title" -ForegroundColor Yellow
    Write-Host "  ⌨️  按 'Q' 或 'Esc' 返回主菜单" -ForegroundColor Green
    Write-Host "========================================================" -ForegroundColor Cyan

    Get-Content $FilePath -Tail 15
    $stream = [System.IO.File]::Open($FilePath, 'Open', 'Read', 'ReadWrite')
    $reader = New-Object System.IO.StreamReader($stream)
    $reader.BaseStream.Seek(0, [System.IO.SeekOrigin]::End) | Out-Null

    try {
        while ($true) {
            $line = $reader.ReadLine()
            if ($line -ne $null) { Write-Host $line } else { Start-Sleep -Milliseconds 100 }
            if ([System.Console]::KeyAvailable) {
                $key = [System.Console]::ReadKey($true)
                if ($key.Key -eq 'Q' -or $key.Key -eq 'Escape') { break }
            }
        }
    } finally { $reader.Close(); $stream.Close() }
}

# --- 菜单显示 ---
function Show-Menu {
    Draw-Title
    Write-Host "  [ 核心控制 ]" -ForegroundColor Cyan
    Write-Line "1. 启动服务 (Start)" "Green"
    Write-Line "2. 停止服务 (Stop)" "Red"
    Write-Line "3. 重启服务 (Restart)" "Yellow"
    Write-Line "4. 实时监控面板 (Monitor)" "Cyan"
    Write-Host "-----------------------------------" -ForegroundColor DarkGray
    Write-Host "`n  [ 日志管理 ]" -ForegroundColor Cyan
    Write-Line "5. 查看标准日志 (Info Log)" "Gray"
    Write-Line "6. 查看功能日志 (Complete Log)" "Gray"
    Write-Host "-----------------------------------" -ForegroundColor DarkGray
    Write-Host "`n  [ 系统设置 ]" -ForegroundColor Cyan
    Write-Line "7. 检查配置文件 (Check Config)" "White"
    Write-Line "8. 设置开机自启 (AutoStart ON)" "Magenta"
    Write-Line "9. 取消开机自启 (AutoStart OFF)" "DarkMagenta"
    
    Write-Host "========================================================" -ForegroundColor DarkGray
    Write-Host "  0. 停止并退出    Q. 仅退出脚本" -ForegroundColor Gray
    Write-Host "========================================================" -ForegroundColor DarkGray
}

# --- 功能实现 ---

function Start-App {
    if (Get-Process -Name $ExeName -ErrorAction SilentlyContinue) {
        Write-Warning "Sing-box 已经在运行中 (PID: $((Get-Process -Name $ExeName).Id))。"
        return
    }
    if (-not (Test-Path $ExePath)) { Write-Error "未找到 $ExePath"; return }

    # 启动前检查日志
    Check-LogSize $LogFile
    Check-LogSize $ErrorLogFile

    Write-Host "  🚀 正在启动 $ExeName ..." -NoNewline
    try {
        Start-Process -FilePath $ExePath -ArgumentList "run -c $ConfigPath" -WindowStyle Hidden -RedirectStandardOutput $LogFile -RedirectStandardError $ErrorLogFile -ErrorAction Stop
        Start-Sleep -Seconds 2
        
        $proc = Get-Process -Name $ExeName -ErrorAction SilentlyContinue
        if ($proc) {
            Write-Host " [成功]" -ForegroundColor Green
            Write-Host "    -> 进程 ID (PID) : $($proc.Id)" -ForegroundColor Magenta
            Write-Host "    -> 启动时间      : $($proc.StartTime)" -ForegroundColor DarkGray
            Write-Host "    -> 内存占用      : $([math]::Round($proc.WorkingSet64 / 1MB, 2)) MB" -ForegroundColor DarkGray
        } else {
            Write-Host " [失败]" -ForegroundColor Red
            Write-Host "启动失败，正在打开功能日志..." -ForegroundColor Yellow
            Start-Sleep -Seconds 1
            View-FuncLog
        }
    } catch { Write-Error $_ }
}

function Stop-App {
    $proc = Get-Process -Name $ExeName -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Host "  🛑 正在停止 Sing-box (PID: $($proc.Id))..." -NoNewline
        Stop-Process -Name $ExeName -Force
        Write-Host " [已停止]" -ForegroundColor Red
    } else { Write-Line "Sing-box 未运行" "DarkGray" }
}

function Restart-App { Stop-App; Start-Sleep -Seconds 1; Start-App }

function Get-Status {
    try { [Console]::CursorVisible = $false } catch {}
    try {
        while ($true) {
            Clear-Host
            Write-Host $TitleArt -ForegroundColor Cyan
            Write-Host "============== [ 📊 实时监控面板 ] ==============" -ForegroundColor Yellow
            Write-Host "       (按 'Q' 或 'Esc' 返回主菜单)" -ForegroundColor DarkGray
            Write-Host "========================================================" -ForegroundColor Cyan

            $proc = Get-Process -Name $ExeName -ErrorAction SilentlyContinue
            if ($proc) {
                $proc.Refresh()
                $uptime = (Get-Date) - $proc.StartTime
                $uptimeStr = "{0:D2}:{1:D2}:{2:D2}" -f $uptime.Hours, $uptime.Minutes, $uptime.Seconds
                if ($uptime.Days -gt 0) { $uptimeStr = "$($uptime.Days)天 $uptimeStr" }
                
                Write-Host ""
                Write-Host "  ● 状态      : 运行中 (Running)" -ForegroundColor Green
                Write-Host "  🆔 PID      : $($proc.Id)" -ForegroundColor Magenta
                Write-Host "  💾 内存占用 : $([math]::Round($proc.WorkingSet64 / 1MB, 2)) MB" -ForegroundColor Cyan
                Write-Host "  ⏱ 运行时间 : $uptimeStr" -ForegroundColor Yellow
                Write-Host "  🧵 线程数   : $($proc.Threads.Count)" -ForegroundColor DarkGray
                Write-Host ""
            } else {
                Write-Host ""
                Write-Host "  ● 状态      : 未运行 (Stopped)" -ForegroundColor Red
                Write-Host ""
                Write-Host "  等待启动..." -ForegroundColor DarkGray
            }
            Write-Host "========================================================" -ForegroundColor Cyan

            for ($i = 0; $i -lt 10; $i++) {
                if ([System.Console]::KeyAvailable) {
                    $key = [System.Console]::ReadKey($true)
                    if ($key.Key -eq 'Q' -or $key.Key -eq 'Escape') { return }
                }
                Start-Sleep -Milliseconds 100
            }
        }
    } finally { try { [Console]::CursorVisible = $true } catch {} }
}

function View-Log {
    if (Test-Path $LogFile) { Watch-LogFile -FilePath $LogFile -Title "标准日志 (Standard Log)" } 
    else { Write-Line "日志文件不存在" "Yellow" }
}

function View-FuncLog {
    if (Test-Path $ErrorLogFile) { Watch-LogFile -FilePath $ErrorLogFile -Title "功能日志 (Function Log)" } 
    else { Write-Line "功能日志文件不存在" "Yellow" }
}

function Test-Config {
    Clear-Host
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "  🛠  配置文件检查" -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Cyan
    
    if (-not (Test-Path $ConfigPath)) { Write-Line "❌ 错误: 找不到文件 $ConfigPath" "Red"; Pause; return }

    try {
        $process = Start-Process -FilePath $ExePath -ArgumentList "check -c $ConfigPath" -NoNewWindow -Wait -PassThru
        Write-Host "" 
        if ($process.ExitCode -eq 0) {
            Write-Line "✅ 校验通过 (PASS)" "Green"
            Write-Line "配置文件 JSON 格式正确。" "Gray"
        } else {
            Write-Line "❌ 校验失败 (FAIL)" "Red"
            Write-Line "请检查上方的错误提示修正配置。" "Yellow"
        }
    } catch { Write-Error "无法执行检查命令" }

    Write-Host "`n  按任意键返回..." -ForegroundColor DarkGray
    [void][System.Console]::ReadKey($true)
}

function Install-Task {
    if (-not (Check-Admin)) { return }
    $Action = New-ScheduledTaskAction -Execute (Convert-Path $ExePath) -Argument "run -c `"$((Convert-Path $ConfigPath))`"" -WorkingDirectory $ScriptDir
    Register-ScheduledTask -TaskName "SingBox_AutoStart" -Action $Action -Trigger (New-ScheduledTaskTrigger -AtLogOn) -Principal (New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest) -Force | Out-Null
    Write-Line "✅ 已设置开机自启 (System级别)" "Green"
}

function Uninstall-Task {
    if (-not (Check-Admin)) { return }
    Unregister-ScheduledTask -TaskName "SingBox_AutoStart" -Confirm:$false -ErrorAction SilentlyContinue
    Write-Line "✅ 已取消开机自启" "Green"
}

# --- 主循环 ---
if (-not (Check-Admin)) { Start-Sleep -Seconds 1 }

while ($true) {
    Show-Menu
    $selection = Read-Host "  请输入选项"
    switch ($selection) {
        "1" { Start-App; Pause }
        "2" { Stop-App; Pause }
        "3" { Restart-App; Pause }
        "4" { Get-Status }
        "5" { View-Log }
        "6" { View-FuncLog }
        "7" { Test-Config }
        "8" { Install-Task; Pause }
        "9" { Uninstall-Task; Pause }
        "0" { Stop-App; Write-Line "正在退出..." "Gray"; Start-Sleep -Seconds 1; exit }
        "Q" { exit }
        "q" { exit }
        Default { Write-Line "无效选项" "Red"; Start-Sleep -Seconds 1 }
    }
}
