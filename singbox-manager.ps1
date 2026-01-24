<#
.SYNOPSIS
    Sing-box 管理脚本 (严格日志限制 + 配置检查修复版)
.DESCRIPTION
    1. 日志轮转严格执行：超过 1024KB 自动切割，最多保留 3 份备份。
    2. 修复并完善了配置检查功能 (菜单7)，提供明确的 Pass/Fail 反馈。
#>

# --- 配置区域 ---
$ExeName = "sing-box"
$ExePath = ".\sing-box.exe"
$ConfigPath = "config.json"
$LogFile = ".\sing-box.log"            # 标准运行日志
$ErrorLogFile = ".\sing-box_error.log" # 功能日志
$MaxLogSizeBytes = 1024 * 1024         # 日志上限 1024KB (1MB)
$MaxBackups = 3                        # 保留备份数量 (log.1, log.2, log.3)
# ----------------

$ScriptDir = $PSScriptRoot
if ($ScriptDir) { Set-Location $ScriptDir }

# --- 核心辅助函数：带退出键的日志查看器 ---
function Watch-LogFile {
    param ([string]$FilePath, [string]$Title)

    if (-not (Test-Path $FilePath)) { Write-Warning "文件不存在: $FilePath"; return }

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
            if ($line -ne $null) { Write-Host $line } else { Start-Sleep -Milliseconds 100 }
            if ([System.Console]::KeyAvailable) {
                $key = [System.Console]::ReadKey($true)
                if ($key.Key -eq 'Q' -or $key.Key -eq 'Escape') { break }
            }
        }
    } finally { $reader.Close(); $stream.Close() }
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

# --- 核心修复：严格日志轮转逻辑 ---
function Check-LogSize {
    param ([string]$FilePath)
    
    if (-not (Test-Path $FilePath)) { return }

    try {
        $fileItem = Get-Item $FilePath
        # 严格检查：如果文件大小超过限制 (1024KB)
        if ($fileItem.Length -gt $MaxLogSizeBytes) {
            Write-Host "[$($fileItem.Name)] 大小为 $([math]::Round($fileItem.Length/1KB, 2))KB (超过 1024KB)，正在轮转..." -ForegroundColor Yellow
            
            # 1. 删除超出保留数量的最旧备份 (例如 log.3)
            # 循环检查并删除所有超出范围的备份，防止有遗留文件
            $limit = $MaxBackups
            while (Test-Path "$FilePath.$limit") {
                Remove-Item "$FilePath.$limit" -Force -ErrorAction SilentlyContinue
                $limit++ 
            }
            # 这里的逻辑是：先把 .3 删掉，腾出位置
            if (Test-Path "$FilePath.$MaxBackups") { 
                Remove-Item "$FilePath.$MaxBackups" -Force -ErrorAction SilentlyContinue
            }

            # 2. 依次后移旧备份 (log.2 -> log.3, log.1 -> log.2)
            for ($i = $MaxBackups - 1; $i -ge 1; $i--) {
                $next = $i + 1
                if (Test-Path "$FilePath.$i") {
                    Move-Item "$FilePath.$i" "$FilePath.$next" -Force -ErrorAction SilentlyContinue
                }
            }

            # 3. 将当前日志移动为最新的备份 (log -> log.1)
            Move-Item $FilePath "$FilePath.1" -Force -ErrorAction SilentlyContinue
            
            Write-Host "✅ 日志已归档，当前重新计数。" -ForegroundColor Gray
        }
    } catch {
        Write-Warning "日志轮转失败，文件可能被占用 (Sing-box 是否正在运行?)"
    }
}

function Show-Header {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "    Sing-box 管理脚本 (Strict & Fixed)" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Cyan
}

function Show-Menu {
    Show-Header
    Write-Host " 1. 启动 (Start)" -ForegroundColor Green
    Write-Host " 2. 停止 (Stop)" -ForegroundColor Red
    Write-Host " 3. 重启 (Restart)" -ForegroundColor Yellow
    Write-Host " 4. 实时监控状态 (Monitor)" -ForegroundColor Cyan
    Write-Host "------------------------------------------" -ForegroundColor DarkGray
    Write-Host " 5. 查看标准日志 (Info Log)" -ForegroundColor Green
    Write-Host " 6. 查看功能日志 (Complete Log)" -ForegroundColor Red
    Write-Host "------------------------------------------" -ForegroundColor DarkGray
    # 这里是本次修复的重点
    Write-Host " 7. 检查配置文件 (Check Config)" -ForegroundColor Green 
    Write-Host " 8. 设置开机自启 (Auto Start)" -ForegroundColor Magenta
    Write-Host " 9. 取消开机自启 (Disable Startup)" -ForegroundColor DarkMagenta
    Write-Host "------------------------------------------" -ForegroundColor DarkGray
    Write-Host " 0. 停止服务并退出 (Kill & Exit)" -ForegroundColor Red
    Write-Host " Q. 仅退出脚本 (Keep Running)" -ForegroundColor Gray
    Write-Host "==========================================" -ForegroundColor Cyan
}

function Start-App {
    if (Get-Process -Name $ExeName -ErrorAction SilentlyContinue) {
        Write-Warning "Sing-box 已经在运行中 (PID: $((Get-Process -Name $ExeName).Id))。"
        Write-Warning "提示：若需触发日志轮转，请先执行 '3. 重启'。"
        return
    }
    if (-not (Test-Path $ExePath)) { Write-Error "未找到 $ExePath"; return }

    # 启动前执行日志检查
    Check-LogSize $LogFile
    Check-LogSize $ErrorLogFile

    Write-Host "正在后台启动 $ExeName ..." -NoNewline
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
        Write-Host "正在停止 Sing-box (PID: $($proc.Id))..." -NoNewline
        Stop-Process -Name $ExeName -Force
        Write-Host " [已停止]" -ForegroundColor Red
    } else { Write-Warning "Sing-box 未运行" }
}

function Restart-App { Stop-App; Start-Sleep -Seconds 1; Start-App }

function Get-Status {
    try { [Console]::CursorVisible = $false } catch {}

    try {
        while ($true) {
            Clear-Host
            Write-Host "==========================================" -ForegroundColor Cyan
            Write-Host "    Sing-box 实时监控面板 (Live)" -ForegroundColor Yellow
            Write-Host "    [按 'Q' 或 'Esc' 键返回菜单]" -ForegroundColor Green
            Write-Host "==========================================" -ForegroundColor Cyan

            $proc = Get-Process -Name $ExeName -ErrorAction SilentlyContinue

            if ($proc) {
                $proc.Refresh()
                
                $uptime = (Get-Date) - $proc.StartTime
                $uptimeStr = "{0:D2}:{1:D2}:{2:D2}" -f $uptime.Hours, $uptime.Minutes, $uptime.Seconds
                if ($uptime.Days -gt 0) { $uptimeStr = "$($uptime.Days)天 $uptimeStr" }

                Write-Host "✅ Sing-box 正在运行" -ForegroundColor Green
                Write-Host "    -> 进程 ID (PID) : $($proc.Id)" -ForegroundColor Magenta
                Write-Host "    -> 内存占用      : $([math]::Round($proc.WorkingSet64 / 1MB, 2)) MB" -ForegroundColor Cyan
                Write-Host "    -> 运行时间      : $uptimeStr" -ForegroundColor Yellow
                Write-Host "    -> 句柄/线程     : $($proc.HandleCount) / $($proc.Threads.Count)" -ForegroundColor DarkGray
                
                # 端口监听已移除
                
            } else {
                Write-Host "❌ Sing-box 未运行" -ForegroundColor Red
                Write-Host "`n等待程序启动..." -ForegroundColor Gray
            }

            for ($i = 0; $i -lt 10; $i++) {
                if ([System.Console]::KeyAvailable) {
                    $key = [System.Console]::ReadKey($true)
                    if ($key.Key -eq 'Q' -or $key.Key -eq 'Escape') { return }
                }
                Start-Sleep -Milliseconds 100
            }
        }
    } finally {
        try { [Console]::CursorVisible = $true } catch {}
    }
}

function View-Log {
    if (Test-Path $LogFile) { Watch-LogFile -FilePath $LogFile -Title "正在查看标准日志 (Info)" } 
    else { Write-Warning "日志文件不存在" }
}

function View-FuncLog {
    if (Test-Path $ErrorLogFile) { Watch-LogFile -FilePath $ErrorLogFile -Title "正在查看功能日志 (Function Log)" } 
    else { Write-Warning "功能日志文件不存在" }
}

# --- 核心修复：完善的配置检查函数 ---
function Test-Config {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "    正在检查配置文件语法..." -ForegroundColor Yellow
    Write-Host "    目标文件: $ConfigPath" -ForegroundColor Gray
    Write-Host "==========================================" -ForegroundColor Cyan
    
    if (-not (Test-Path $ConfigPath)) {
        Write-Host "❌ 错误: 找不到文件 $ConfigPath" -ForegroundColor Red
        Pause
        return
    }

    # 执行检查并捕获结果
    # 使用 Wait 和 PassThru 获取退出代码
    try {
        $process = Start-Process -FilePath $ExePath `
                                 -ArgumentList "check -c $ConfigPath" `
                                 -NoNewWindow `
                                 -Wait `
                                 -PassThru
        
        Write-Host "" 
        if ($process.ExitCode -eq 0) {
            Write-Host "✅ 校验通过 (SUCCESS)" -ForegroundColor Green
            Write-Host "配置文件的 JSON 格式和参数结构正确。" -ForegroundColor Gray
        } else {
            Write-Host "❌ 校验失败 (FAILED)" -ForegroundColor Red
            Write-Host "请根据上方提示的错误信息 (FATAL/ERROR) 修正 config.json。" -ForegroundColor Yellow
        }
    } catch {
        Write-Error "无法执行检查命令: $_"
    }

    Write-Host "`n按任意键返回菜单..." -ForegroundColor Gray
    [void][System.Console]::ReadKey($true)
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
        "4" { Get-Status }
        "5" { View-Log }
        "6" { View-FuncLog }
        "7" { Test-Config } # 这里不需要Pause，因为函数内部自己加了
        "8" { Install-Task; Pause }
        "9" { Uninstall-Task; Pause }
        "0" { Stop-App; Write-Host "退出中..."; Start-Sleep -Seconds 1; exit }
        "Q" { exit }
        "q" { exit }
        Default { Write-Warning "无效选项"; Start-Sleep -Seconds 1 }
    }
}
