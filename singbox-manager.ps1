# sing-box Windows 管理脚本（简化版）
# 需要以管理员权限运行

param (
    [string]$Action = "",
    [string]$ConfigPath = "config.json",
    [switch]$InstallTask,
    [switch]$UninstallTask,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

# 脚本信息
$ScriptVersion = "1.0.0"
$ScriptName = "sing-box Manager"

# 获取脚本所在目录
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$SingBoxDir = if (Test-Path "$ScriptDir\sing-box.exe") { $ScriptDir } else { $ScriptDir }

# 日志文件路径
$LogFile = Join-Path $SingBoxDir "sing-box.log"

function Show-Header {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "         $ScriptName v$ScriptVersion" -ForegroundColor Yellow
    Write-Host "         Windows 管理脚本" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "当前目录: $SingBoxDir"
    Write-Host "配置文件: $ConfigPath"
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
}

function Show-Menu {
    Show-Header
    Write-Host "请选择操作:" -ForegroundColor Yellow
    Write-Host " 1. 启动 sing-box" -ForegroundColor Green
    Write-Host " 2. 停止 sing-box" -ForegroundColor Red
    Write-Host " 3. 重启 sing-box" -ForegroundColor Yellow
    Write-Host " 4. 查看运行状态" -ForegroundColor Cyan
    Write-Host " 5. 查看实时日志" -ForegroundColor Magenta
    Write-Host " 6. 检查配置文件" -ForegroundColor Gray
    Write-Host " 7. 安装为计划任务" -ForegroundColor Green
    Write-Host " 8. 卸载计划任务" -ForegroundColor Red
    Write-Host " 0. 退出" -ForegroundColor DarkGray
    Write-Host ""
}

function Check-Admin {
    if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Host "需要管理员权限运行此脚本！" -ForegroundColor Red
        Write-Host "请右键点击 PowerShell，选择'以管理员身份运行'" -ForegroundColor Yellow
        Read-Host "按 Enter 键退出"
        exit 1
    }
}

function Check-SingBox {
    $singboxExe = Join-Path $SingBoxDir "sing-box.exe"
    if (-not (Test-Path $singboxExe)) {
        Write-Host "错误: 未找到 sing-box.exe" -ForegroundColor Red
        Write-Host "请将脚本放在 sing-box 目录中" -ForegroundColor Yellow
        return $false
    }
    return $true
}

function Start-SingBox {
    param([string]$ConfigFile = $ConfigPath)
    
    if (-not (Check-SingBox)) { return }
    
    $config = Join-Path $SingBoxDir $ConfigFile
    if (-not (Test-Path $config)) {
        Write-Host "错误: 未找到配置文件 $config" -ForegroundColor Red
        return
    }
    
    # 检查是否已运行
    $process = Get-Process sing-box -ErrorAction SilentlyContinue
    if ($process) {
        Write-Host "sing-box 已在运行 (PID: $($process.Id))" -ForegroundColor Yellow
        return
    }
    
    Write-Host "正在启动 sing-box..." -ForegroundColor Green
    $exePath = Join-Path $SingBoxDir "sing-box.exe"
    
    # 启动进程
    Start-Process -FilePath $exePath -ArgumentList "run -c `"$config`"" -NoNewWindow -PassThru -RedirectStandardOutput $LogFile
    
    Start-Sleep -Seconds 2
    
    $process = Get-Process sing-box -ErrorAction SilentlyContinue
    if ($process) {
        Write-Host "✅ sing-box 启动成功 (PID: $($process.Id))" -ForegroundColor Green
    }
    else {
        Write-Host "❌ sing-box 启动失败" -ForegroundColor Red
    }
}

function Stop-SingBox {
    $process = Get-Process sing-box -ErrorAction SilentlyContinue
    if ($process) {
        Write-Host "正在停止 sing-box..." -ForegroundColor Yellow
        Stop-Process -Name "sing-box" -Force
        Start-Sleep -Seconds 1
        
        $process = Get-Process sing-box -ErrorAction SilentlyContinue
        if (-not $process) {
            Write-Host "✅ sing-box 已停止" -ForegroundColor Green
        }
        else {
            Write-Host "❌ 停止失败" -ForegroundColor Red
        }
    }
    else {
        Write-Host "sing-box 未运行" -ForegroundColor Yellow
    }
}

function Restart-SingBox {
    Stop-SingBox
    Start-Sleep -Seconds 2
    Start-SingBox
}

function Get-Status {
    $process = Get-Process sing-box -ErrorAction SilentlyContinue
    if ($process) {
        Write-Host "✅ sing-box 正在运行" -ForegroundColor Green
        Write-Host "   PID: $($process.Id)" -ForegroundColor Cyan
        Write-Host "   启动时间: $($process.StartTime)" -ForegroundColor Cyan
        Write-Host "   内存使用: $([math]::Round($process.WorkingSet64 / 1MB, 2)) MB" -ForegroundColor Cyan
        
        # 检查端口
        $ports = @(2080, 2081, 1080, 1081, 7890)
        foreach ($port in $ports) {
            $listening = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
            if ($listening) {
                Write-Host "   端口 $port 正在监听" -ForegroundColor Green
            }
        }
    }
    else {
        Write-Host "❌ sing-box 未运行" -ForegroundColor Red
    }
}

function Show-Logs {
    if (Test-Path $LogFile) {
        Write-Host "正在显示日志 (Ctrl+C 退出)..." -ForegroundColor Yellow
        Write-Host "------------------------------------------" -ForegroundColor Gray
        Get-Content -Path $LogFile -Tail 50 -Wait
    }
    else {
        Write-Host "日志文件不存在" -ForegroundColor Yellow
    }
}

function Test-Config {
    if (-not (Check-SingBox)) { return }
    
    $exePath = Join-Path $SingBoxDir "sing-box.exe"
    $config = Join-Path $SingBoxDir $ConfigPath
    
    if (-not (Test-Path $config)) {
        Write-Host "配置文件不存在: $config" -ForegroundColor Red
        return
    }
    
    Write-Host "正在检查配置文件..." -ForegroundColor Yellow
    & $exePath check -c $config
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ 配置文件语法正确" -ForegroundColor Green
    }
    else {
        Write-Host "❌ 配置文件有错误" -ForegroundColor Red
    }
}

function Install-ScheduledTask {
    $taskName = "sing-box"
    $exePath = Join-Path $SingBoxDir "sing-box.exe"
    $config = Join-Path $SingBoxDir $ConfigPath
    
    $action = New-ScheduledTaskAction -Execute $exePath -Argument "run -c `"$config`"" -WorkingDirectory $SingBoxDir
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force
    
    Write-Host "✅ 计划任务安装完成" -ForegroundColor Green
    Write-Host "任务名称: $taskName" -ForegroundColor Cyan
    Write-Host "触发条件: 系统启动时" -ForegroundColor Cyan
}

function Uninstall-Task {
    $taskName = "sing-box"
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "✅ 计划任务已卸载" -ForegroundColor Green
}

function Show-Help {
    Show-Header
    Write-Host "使用说明:" -ForegroundColor Yellow
    Write-Host " 直接运行: .\singbox-manager.ps1" -ForegroundColor Cyan
    Write-Host " 命令行参数:" -ForegroundColor Cyan
    Write-Host "   -Action [start|stop|restart|status]" -ForegroundColor Green
    Write-Host "   -ConfigPath <路径>   指定配置文件" -ForegroundColor Green
    Write-Host "   -InstallTask         安装为计划任务" -ForegroundColor Green
    Write-Host "   -UninstallTask       卸载计划任务" -ForegroundColor Green
    Write-Host "   -Help                显示帮助" -ForegroundColor Green
    Write-Host ""
    Write-Host "示例:" -ForegroundColor Yellow
    Write-Host "  .\singbox-manager.ps1 -Action start" -ForegroundColor Cyan
    Write-Host "  .\singbox-manager.ps1 -InstallTask" -ForegroundColor Cyan
    Write-Host ""
}

# 主程序
function Main {
    # 检查参数
    if ($Help) {
        Show-Help
        return
    }
    
    # 如果有命令行参数，直接执行
    switch ($Action.ToLower()) {
        "start" { Start-SingBox; return }
        "stop" { Stop-SingBox; return }
        "restart" { Restart-SingBox; return }
        "status" { Get-Status; return }
    }
    
    if ($InstallTask) {
        Check-Admin
        Install-ScheduledTask
        return
    }
    
    if ($UninstallTask) {
        Check-Admin
        Uninstall-Task
        return
    }
    
    # 交互式菜单
    do {
        Show-Menu
        $choice = Read-Host "请选择 [0-8]"
        
        switch ($choice) {
            "1" { 
                Start-SingBox
                Pause
            }
            "2" { 
                Stop-SingBox
                Pause
            }
            "3" { 
                Restart-SingBox
                Pause
            }
            "4" { 
                Get-Status
                Pause
            }
            "5" { 
                Show-Logs
                Pause
            }
            "6" { 
                Test-Config
                Pause
            }
            "7" { 
                Check-Admin
                Install-ScheduledTask
                Pause
            }
            "8" { 
                Check-Admin
                Uninstall-Task
                Pause
            }
            "0" { 
                Write-Host "再见！" -ForegroundColor Cyan
                return
            }
            default {
                Write-Host "无效选择" -ForegroundColor Red
                Pause
            }
        }
    } while ($true)
}

# 运行主程序
try {
    Main
}
catch {
    Write-Host "错误: $_" -ForegroundColor Red
    Pause
}