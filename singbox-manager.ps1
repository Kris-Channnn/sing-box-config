# sing-box Windows 管理脚本
# 需要以管理员权限运行

param (
    [string]$Action = "",
    [string]$ConfigPath = "config.json",
    [switch]$InstallService,
    [switch]$UninstallService,
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
$ServiceLog = Join-Path $SingBoxDir "service.log"

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
    Write-Host " 7. 测试网络连接" -ForegroundColor Blue
    Write-Host " 8. 安装为系统服务 (nssm)" -ForegroundColor Green
    Write-Host " 9. 卸载系统服务" -ForegroundColor Red
    Write-Host "10. 安装为计划任务" -ForegroundColor Green
    Write-Host "11. 卸载计划任务" -ForegroundColor Red
    Write-Host "12. 生成配置文件模板" -ForegroundColor Yellow
    Write-Host "13. 更新 sing-box" -ForegroundColor Cyan
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

function Test-Connection {
    Write-Host "测试网络连接..." -ForegroundColor Yellow
    
    # 测试本地代理
    $proxyTest = Test-NetConnection -ComputerName "www.google.com" -Port 443 -InformationLevel Quiet
    $directTest = Test-NetConnection -ComputerName "www.baidu.com" -Port 443 -InformationLevel Quiet
    
    Write-Host "本地网络: $(if ($directTest) {'✅ 正常'} else {'❌ 失败'})" -ForegroundColor $(if ($directTest) { 'Green' } else { 'Red' })
    
    # 测试代理（假设使用 7890 端口）
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.Proxy = New-Object System.Net.WebProxy("127.0.0.1:7890")
        $result = $webClient.DownloadString("http://ipinfo.io/ip") -replace "`n", ""
        Write-Host "代理连接: ✅ 正常 (IP: $result)" -ForegroundColor Green
    }
    catch {
        Write-Host "代理连接: ❌ 失败" -ForegroundColor Red
    }
}

function Install-NssmService {
    if (-not (Check-SingBox)) { return }
    
    $nssmPath = Join-Path $SingBoxDir "nssm.exe"
    if (-not (Test-Path $nssmPath)) {
        Write-Host "正在下载 nssm..." -ForegroundColor Yellow
        $nssmUrl = "https://nssm.cc/release/nssm-2.24.zip"
        $tempZip = Join-Path $env:TEMP "nssm.zip"
        
        Invoke-WebRequest -Uri $nssmUrl -OutFile $tempZip
        Expand-Archive -Path $tempZip -DestinationPath $env:TEMP\ -Force
        
        $nssmExe = Get-ChildItem -Path $env:TEMP -Filter "nssm.exe" -Recurse | Select-Object -First 1
        if ($nssmExe) {
            Copy-Item -Path $nssmExe.FullName -Destination $nssmPath
            Write-Host "✅ nssm 下载完成" -ForegroundColor Green
        }
        else {
            Write-Host "❌ 下载 nssm 失败" -ForegroundColor Red
            return
        }
    }
    
    $serviceName = "sing-box"
    $exePath = Join-Path $SingBoxDir "sing-box.exe"
    $config = Join-Path $SingBoxDir $ConfigPath
    
    Write-Host "正在安装服务..." -ForegroundColor Yellow
    
    # 检查服务是否存在
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($service) {
        Write-Host "服务已存在，正在重新安装..." -ForegroundColor Yellow
        & $nssmPath remove $serviceName confirm
    }
    
    # 安装服务
    & $nssmPath install $serviceName $exePath "run -c `"$config`""
    & $nssmPath set $serviceName Description "sing-box Proxy Service"
    & $nssmPath set $serviceName Start SERVICE_AUTO_START
    & $nssmPath set $serviceName AppStdout $ServiceLog
    & $nssmPath set $serviceName AppStderr $ServiceLog
    
    Start-Service -Name $serviceName
    Write-Host "✅ sing-box 服务安装完成" -ForegroundColor Green
    Write-Host "服务名称: $serviceName" -ForegroundColor Cyan
    Write-Host "启动类型: 自动" -ForegroundColor Cyan
}

function Uninstall-Service {
    $serviceName = "sing-box"
    $nssmPath = Join-Path $SingBoxDir "nssm.exe"
    
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($service) {
        Write-Host "正在卸载服务..." -ForegroundColor Yellow
        
        if ($service.Status -ne 'Stopped') {
            Stop-Service -Name $serviceName -Force
        }
        
        if (Test-Path $nssmPath) {
            & $nssmPath remove $serviceName confirm
        }
        else {
            sc.exe delete $serviceName
        }
        
        Write-Host "✅ 服务已卸载" -ForegroundColor Green
    }
    else {
        Write-Host "服务不存在" -ForegroundColor Yellow
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

function Generate-ConfigTemplate {
    $template = @'
{
  "log": {
    "disabled": false,
    "level": "info",
    "output": "sing-box.log",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "google",
        "address": "tls://8.8.8.8"
      },
      {
        "tag": "local",
        "address": "223.5.5.5",
        "detour": "direct"
      }
    ],
    "rules": [
      {
        "outbound": "any",
        "server": "local"
      }
    ]
  },
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "127.0.0.1",
      "listen_port": 2080,
      "sniff": true
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "rules": [
      {
        "protocol": "dns",
        "outbound": "direct"
      },
      {
        "domain_keyword": [
          "google",
          "github"
        ],
        "geosite": [
          "category-ads-all"
        ],
        "outbound": "block"
      }
    ],
    "auto_detect_interface": true
  }
}
'@
    
    $configFile = Join-Path $SingBoxDir "config.example.json"
    $template | Out-File -FilePath $configFile -Encoding UTF8
    
    Write-Host "✅ 配置文件模板已生成: $configFile" -ForegroundColor Green
}

function Update-SingBox {
    Write-Host "正在检查最新版本..." -ForegroundColor Yellow
    
    try {
        $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/SagerNet/sing-box/releases/latest"
        $asset = $latestRelease.assets | Where-Object { $_.name -like "*windows-amd64*" } | Select-Object -First 1
        
        if ($asset) {
            Write-Host "最新版本: $($latestRelease.tag_name)" -ForegroundColor Cyan
            Write-Host "正在下载..." -ForegroundColor Yellow
            
            $tempFile = Join-Path $env:TEMP "sing-box.zip"
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tempFile
            
            # 备份旧版本
            $backupDir = Join-Path $SingBoxDir "backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
            Copy-Item "$SingBoxDir\sing-box.exe" "$backupDir\" -ErrorAction SilentlyContinue
            
            # 解压新版本
            Expand-Archive -Path $tempFile -DestinationPath $env:TEMP\sing-box-new -Force
            $extracted = Get-ChildItem -Path "$env:TEMP\sing-box-new" -Filter "sing-box.exe" -Recurse | Select-Object -First 1
            
            if ($extracted) {
                Copy-Item -Path $extracted.FullName -Destination "$SingBoxDir\sing-box.exe" -Force
                Write-Host "✅ sing-box 更新完成" -ForegroundColor Green
                Write-Host "旧版本已备份到: $backupDir" -ForegroundColor Cyan
            }
        }
    }
    catch {
        Write-Host "❌ 更新失败: $_" -ForegroundColor Red
    }
}

function Show-Help {
    Show-Header
    Write-Host "使用说明:" -ForegroundColor Yellow
    Write-Host " 直接运行: .\singbox-manager.ps1" -ForegroundColor Cyan
    Write-Host " 命令行参数:" -ForegroundColor Cyan
    Write-Host "   -Action [start|stop|restart|status]" -ForegroundColor Green
    Write-Host "   -ConfigPath <路径>   指定配置文件" -ForegroundColor Green
    Write-Host "   -InstallService      安装为系统服务" -ForegroundColor Green
    Write-Host "   -UninstallService    卸载系统服务" -ForegroundColor Green
    Write-Host "   -InstallTask         安装为计划任务" -ForegroundColor Green
    Write-Host "   -UninstallTask       卸载计划任务" -ForegroundColor Green
    Write-Host "   -Help                显示帮助" -ForegroundColor Green
    Write-Host ""
    Write-Host "示例:" -ForegroundColor Yellow
    Write-Host "  .\singbox-manager.ps1 -Action start" -ForegroundColor Cyan
    Write-Host "  .\singbox-manager.ps1 -InstallService" -ForegroundColor Cyan
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
    
    if ($InstallService) {
        Check-Admin
        Install-NssmService
        return
    }
    
    if ($UninstallService) {
        Check-Admin
        Uninstall-Service
        return
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
        $choice = Read-Host "请选择 [0-13]"
        
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
                Test-Connection
                Pause
            }
            "8" { 
                Check-Admin
                Install-NssmService
                Pause
            }
            "9" { 
                Check-Admin
                Uninstall-Service
                Pause
            }
            "10" { 
                Check-Admin
                Install-ScheduledTask
                Pause
            }
            "11" { 
                Check-Admin
                Uninstall-Task
                Pause
            }
            "12" { 
                Generate-ConfigTemplate
                Pause
            }
            "13" { 
                Update-SingBox
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
