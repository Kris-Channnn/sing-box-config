# sing-box Windows 管理脚本 - 固定配置路径版本
# 需要以管理员权限运行

param (
    [string]$Action = "",
    [switch]$Help
)

$ErrorActionPreference = "Stop"

# 脚本信息
$ScriptVersion = "1.0.0"
$ScriptName = "sing-box Manager"

# 固定配置路径
$SingBoxDir = "D:\APPLY\sing-box_reF1nd"
$ConfigPath = "D:\APPLY\sing-box_reF1nd\config.json"

# 日志文件路径
$LogFile = Join-Path $SingBoxDir "sing-box.log"
$ServiceLog = Join-Path $SingBoxDir "service.log"

function Show-Header {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "         $ScriptName v$ScriptVersion" -ForegroundColor Yellow
    Write-Host "     固定路径: D:\APPLY\sing-box_reF1nd" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "sing-box目录: $SingBoxDir"
    Write-Host "配置文件: $ConfigPath"
    Write-Host "日志文件: $LogFile"
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
    Write-Host "14. 打开配置文件" -ForegroundColor White
    Write-Host "15. 打开日志目录" -ForegroundColor White
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
        Write-Host "路径: $singboxExe" -ForegroundColor Yellow
        Write-Host "请确保 sing-box.exe 存在于指定目录" -ForegroundColor Yellow
        return $false
    }
    return $true
}

function Check-Config {
    if (-not (Test-Path $ConfigPath)) {
        Write-Host "警告: 配置文件不存在" -ForegroundColor Yellow
        Write-Host "路径: $ConfigPath" -ForegroundColor Yellow
        return $false
    }
    return $true
}

function Start-SingBox {
    if (-not (Check-SingBox)) { return }
    
    if (-not (Check-Config)) {
        $createConfig = Read-Host "是否创建默认配置文件? (y/n)"
        if ($createConfig -eq 'y') {
            Generate-ConfigTemplate
            Write-Host "请编辑配置文件后重试" -ForegroundColor Yellow
            Start-Process notepad $ConfigPath
            return
        } else {
            Write-Host "未启动 sing-box" -ForegroundColor Red
            return
        }
    }
    
    # 检查是否已运行
    $process = Get-Process sing-box -ErrorAction SilentlyContinue
    if ($process) {
        Write-Host "sing-box 已在运行 (PID: $($process.Id))" -ForegroundColor Yellow
        return
    }
    
    Write-Host "正在启动 sing-box..." -ForegroundColor Green
    $exePath = Join-Path $SingBoxDir "sing-box.exe"
    
    # 创建日志目录（如果不存在）
    $logDir = Split-Path $LogFile -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    # 启动进程
    Start-Process -FilePath $exePath -ArgumentList "run -c `"$ConfigPath`"" -NoNewWindow -PassThru -RedirectStandardOutput $LogFile
    
    Start-Sleep -Seconds 2
    
    $process = Get-Process sing-box -ErrorAction SilentlyContinue
    if ($process) {
        Write-Host "✅ sing-box 启动成功 (PID: $($process.Id))" -ForegroundColor Green
        Write-Host "配置文件: $ConfigPath" -ForegroundColor Cyan
    } else {
        Write-Host "❌ sing-box 启动失败" -ForegroundColor Red
        Write-Host "请检查配置文件或查看日志: $LogFile" -ForegroundColor Yellow
    }
}

function Stop-SingBox {
    $process = Get-Process sing-box -ErrorAction SilentlyContinue
    if ($process) {
        Write-Host "正在停止 sing-box..." -ForegroundColor Yellow
        $pids = $process.Id -join ", "
        Stop-Process -Name "sing-box" -Force
        Start-Sleep -Seconds 1
        
        $process = Get-Process sing-box -ErrorAction SilentlyContinue
        if (-not $process) {
            Write-Host "✅ sing-box 已停止 (PID: $pids)" -ForegroundColor Green
        } else {
            Write-Host "❌ 停止失败" -ForegroundColor Red
        }
    } else {
        Write-Host "sing-box 未运行" -ForegroundColor Yellow
    }
}

function Restart-SingBox {
    Stop-SingBox
    Start-Sleep -Seconds 2
    Start-SingBox
}

function Get-Status {
    Show-Header
    
    # 检查目录存在
    if (-not (Test-Path $SingBoxDir)) {
        Write-Host "❌ sing-box 目录不存在: $SingBoxDir" -ForegroundColor Red
        return
    }
    
    # 检查程序文件
    if (-not (Test-Path (Join-Path $SingBoxDir "sing-box.exe"))) {
        Write-Host "❌ sing-box.exe 不存在" -ForegroundColor Red
    } else {
        Write-Host "✅ sing-box.exe 存在" -ForegroundColor Green
    }
    
    # 检查配置文件
    if (-not (Test-Path $ConfigPath)) {
        Write-Host "❌ 配置文件不存在" -ForegroundColor Red
    } else {
        Write-Host "✅ 配置文件存在" -ForegroundColor Green
        $configSize = (Get-Item $ConfigPath).Length / 1KB
        Write-Host "   文件大小: $([math]::Round($configSize, 2)) KB" -ForegroundColor Gray
    }
    
    # 检查进程状态
    $process = Get-Process sing-box -ErrorAction SilentlyContinue
    if ($process) {
        Write-Host "✅ sing-box 正在运行" -ForegroundColor Green
        Write-Host "   PID: $($process.Id)" -ForegroundColor Cyan
        Write-Host "   启动时间: $($process.StartTime)" -ForegroundColor Cyan
        Write-Host "   内存使用: $([math]::Round($process.WorkingSet64 / 1MB, 2)) MB" -ForegroundColor Cyan
        
        # 检查常用端口
        $ports = @(2080, 2081, 1080, 1081, 7890, 7891)
        foreach ($port in $ports) {
            $listening = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
            if ($listening) {
                Write-Host "   端口 $port 正在监听" -ForegroundColor Green
            }
        }
        
        # 显示配置文件路径
        $cmdline = (Get-WmiObject Win32_Process -Filter "name = 'sing-box.exe'").CommandLine
        Write-Host "   命令行: $cmdline" -ForegroundColor Gray
    } else {
        Write-Host "❌ sing-box 未运行" -ForegroundColor Red
    }
}

function Show-Logs {
    if (Test-Path $LogFile) {
        Write-Host "正在显示日志 (Ctrl+C 退出)..." -ForegroundColor Yellow
        Write-Host "日志文件: $LogFile" -ForegroundColor Cyan
        Write-Host "------------------------------------------" -ForegroundColor Gray
        Get-Content -Path $LogFile -Tail 100 -Wait
    } else {
        Write-Host "日志文件不存在" -ForegroundColor Yellow
        Write-Host "路径: $LogFile" -ForegroundColor Gray
    }
}

function Test-Config {
    Show-Header
    
    if (-not (Check-SingBox)) { return }
    
    if (-not (Test-Path $ConfigPath)) {
        Write-Host "配置文件不存在: $ConfigPath" -ForegroundColor Red
        return
    }
    
    Write-Host "正在检查配置文件..." -ForegroundColor Yellow
    Write-Host "配置文件: $ConfigPath" -ForegroundColor Cyan
    
    $exePath = Join-Path $SingBoxDir "sing-box.exe"
    & $exePath check -c $ConfigPath
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ 配置文件语法正确" -ForegroundColor Green
    } else {
        Write-Host "❌ 配置文件有错误" -ForegroundColor Red
        Write-Host "请编辑配置文件: $ConfigPath" -ForegroundColor Yellow
    }
}

function Test-Connection {
    Show-Header
    
    Write-Host "测试网络连接..." -ForegroundColor Yellow
    
    # 测试直连网络
    $directTest = Test-NetConnection -ComputerName "www.baidu.com" -Port 443 -InformationLevel Quiet
    Write-Host "直连网络: $(if ($directTest) {'✅ 正常'} else {'❌ 失败'})" -ForegroundColor $(if ($directTest) {'Green'} else {'Red'})
    
    # 测试代理（假设使用 2080 端口）
    Write-Host "测试代理连接 (127.0.0.1:7890)..." -ForegroundColor Yellow
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.Proxy = New-Object System.Net.WebProxy("http://127.0.0.1:7890")
        $webClient.Headers.Add("User-Agent", "Mozilla/5.0")
        $result = $webClient.DownloadString("http://ipinfo.io/ip") -replace "`n", ""
        Write-Host "代理连接: ✅ 正常 (出口 IP: $result)" -ForegroundColor Green
    } catch {
        Write-Host "代理连接: ❌ 失败 (确保 sing-box 正在运行并监听 7890 端口)" -ForegroundColor Red
    }
}

function Install-NssmService {
    Check-Admin
    Show-Header
    
    if (-not (Check-SingBox)) { return }
    if (-not (Check-Config)) { 
        Write-Host "请先创建配置文件" -ForegroundColor Red
        return
    }
    
    $nssmPath = Join-Path $SingBoxDir "nssm.exe"
    if (-not (Test-Path $nssmPath)) {
        Write-Host "正在下载 nssm..." -ForegroundColor Yellow
        $nssmUrl = "https://nssm.cc/release/nssm-2.24.zip"
        $tempZip = Join-Path $env:TEMP "nssm.zip"
        
        try {
            Invoke-WebRequest -Uri $nssmUrl -OutFile $tempZip -UseBasicParsing
            Expand-Archive -Path $tempZip -DestinationPath $env:TEMP\ -Force
            
            $nssmExe = Get-ChildItem -Path $env:TEMP -Filter "nssm.exe" -Recurse | Select-Object -First 1
            if ($nssmExe) {
                Copy-Item -Path $nssmExe.FullName -Destination $nssmPath
                Write-Host "✅ nssm 下载完成" -ForegroundColor Green
            } else {
                Write-Host "❌ 未找到 nssm.exe" -ForegroundColor Red
                return
            }
        } catch {
            Write-Host "❌ 下载 nssm 失败: $_" -ForegroundColor Red
            return
        }
    }
    
    $serviceName = "sing-box"
    $exePath = Join-Path $SingBoxDir "sing-box.exe"
    
    Write-Host "正在安装服务..." -ForegroundColor Yellow
    Write-Host "服务名称: $serviceName" -ForegroundColor Cyan
    Write-Host "程序路径: $exePath" -ForegroundColor Cyan
    Write-Host "配置文件: $ConfigPath" -ForegroundColor Cyan
    
    # 检查服务是否存在
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($service) {
        Write-Host "服务已存在，正在重新安装..." -ForegroundColor Yellow
        & $nssmPath remove $serviceName confirm
        Start-Sleep -Seconds 1
    }
    
    # 安装服务
    & $nssmPath install $serviceName $exePath "run -c `"$ConfigPath`""
    & $nssmPath set $serviceName Description "sing-box Proxy Service"
    & $nssmPath set $serviceName Start SERVICE_AUTO_START
    & $nssmPath set $serviceName AppStdout $ServiceLog
    & $nssmPath set $serviceName AppStderr $ServiceLog
    
    # 设置服务恢复选项
    & $nssmPath set $serviceName AppRestartDelay 5000
    & $nssmPath set $serviceName AppExit Default Restart
    
    Start-Service -Name $serviceName
    Write-Host "✅ sing-box 服务安装完成" -ForegroundColor Green
    Write-Host "服务状态: $(Get-Service -Name $serviceName | Select-Object -ExpandProperty Status)" -ForegroundColor Cyan
}

function Uninstall-Service {
    Check-Admin
    Show-Header
    
    $serviceName = "sing-box"
    $nssmPath = Join-Path $SingBoxDir "nssm.exe"
    
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($service) {
        Write-Host "正在卸载服务..." -ForegroundColor Yellow
        
        if ($service.Status -ne 'Stopped') {
            Stop-Service -Name $serviceName -Force
            Write-Host "服务已停止" -ForegroundColor Green
        }
        
        if (Test-Path $nssmPath) {
            & $nssmPath remove $serviceName confirm
            Write-Host "使用 nssm 卸载服务" -ForegroundColor Cyan
        } else {
            sc.exe delete $serviceName
            Write-Host "使用 sc 删除服务" -ForegroundColor Cyan
        }
        
        Write-Host "✅ 服务已卸载" -ForegroundColor Green
    } else {
        Write-Host "服务不存在" -ForegroundColor Yellow
    }
}

function Install-ScheduledTask {
    Check-Admin
    Show-Header
    
    $taskName = "sing-box"
    $exePath = Join-Path $SingBoxDir "sing-box.exe"
    
    Write-Host "正在安装计划任务..." -ForegroundColor Yellow
    
    # 删除现有任务
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    
    # 创建新任务
    $action = New-ScheduledTaskAction -Execute $exePath -Argument "run -c `"$ConfigPath`"" -WorkingDirectory $SingBoxDir
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force
    
    Write-Host "✅ 计划任务安装完成" -ForegroundColor Green
    Write-Host "任务名称: $taskName" -ForegroundColor Cyan
    Write-Host "触发条件: 系统启动时" -ForegroundColor Cyan
    Write-Host "运行账户: SYSTEM" -ForegroundColor Cyan
}

function Uninstall-Task {
    Check-Admin
    Show-Header
    
    $taskName = "sing-box"
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "✅ 计划任务已卸载" -ForegroundColor Green
}

function Generate-ConfigTemplate {
    Show-Header
    
    $template = @'
{
  "log": {
    "disabled": false,
    "level": "info",
    "output": "D:\\APPLY\\sing-box_reF1nd\\sing-box.log",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "google",
        "address": "tls://8.8.8.8",
        "detour": "proxy"
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
      "type": "socks",
      "tag": "proxy",
      "server": "your-proxy-server.com",
      "server_port": 1080,
      "username": "user",
      "password": "pass"
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
          "github",
          "twitter"
        ],
        "outbound": "proxy"
      }
    ],
    "auto_detect_interface": true
  }
}
'@
    
    $template | Out-File -FilePath $ConfigPath -Encoding UTF8 -Force
    
    Write-Host "✅ 配置文件模板已生成" -ForegroundColor Green
    Write-Host "路径: $ConfigPath" -ForegroundColor Cyan
    
    $editNow = Read-Host "是否立即编辑配置文件? (y/n)"
    if ($editNow -eq 'y') {
        Open-ConfigFile
    }
}

function Update-SingBox {
    Check-Admin
    Show-Header
    
    Write-Host "正在检查最新版本..." -ForegroundColor Yellow
    
    try {
        $latestRelease = Invoke-RestMethod -Uri "https://ghfast.top/https://github.com/DustinWin/proxy-tools/releases/download/sing-box" -UseBasicParsing
        $asset = $latestRelease.assets | Where-Object { $_.name -like "*windows-amd64v3*" } | Select-Object -First 1
        
        if ($asset) {
            Write-Host "最新版本: $($latestRelease.tag_name)" -ForegroundColor Cyan
            Write-Host "发布日期: $($latestRelease.published_at)" -ForegroundColor Cyan
            Write-Host "正在下载..." -ForegroundColor Yellow
            
            $tempFile = Join-Path $env:TEMP "sing-box.zip"
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tempFile -UseBasicParsing
            
            # 备份旧版本
            $backupDir = Join-Path $SingBoxDir "backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
            Copy-Item "$SingBoxDir\sing-box.exe" "$backupDir\" -ErrorAction SilentlyContinue
            
            Write-Host "备份旧版本到: $backupDir" -ForegroundColor Cyan
            
            # 解压新版本
            $extractDir = Join-Path $env:TEMP "sing-box-new"
            if (Test-Path $extractDir) {
                Remove-Item $extractDir -Recurse -Force
            }
            
            Expand-Archive -Path $tempFile -DestinationPath $extractDir -Force
            $extracted = Get-ChildItem -Path $extractDir -Filter "sing-box.exe" -Recurse | Select-Object -First 1
            
            if ($extracted) {
                # 停止运行中的 sing-box
                Stop-SingBox
                Start-Sleep -Seconds 1
                
                # 复制新文件
                Copy-Item -Path $extracted.FullName -Destination "$SingBoxDir\sing-box.exe" -Force
                
                # 复制其他文件
                Get-ChildItem -Path $extracted.DirectoryName -Exclude "*.exe" | Copy-Item -Destination $SingBoxDir -Force -Recurse
                
                Write-Host "✅ sing-box 更新完成" -ForegroundColor Green
                Write-Host "新版本: $($latestRelease.tag_name)" -ForegroundColor Cyan
                Write-Host "旧版本已备份到: $backupDir" -ForegroundColor Cyan
                
                $startNow = Read-Host "是否立即启动新版本? (y/n)"
                if ($startNow -eq 'y') {
                    Start-SingBox
                }
            }
        }
    } catch {
        Write-Host "❌ 更新失败: $_" -ForegroundColor Red
    }
}

function Open-ConfigFile {
    if (Test-Path $ConfigPath) {
        Write-Host "打开配置文件: $ConfigPath" -ForegroundColor Cyan
        Start-Process notepad $ConfigPath
    } else {
        Write-Host "配置文件不存在: $ConfigPath" -ForegroundColor Red
        $createNew = Read-Host "是否创建新配置文件? (y/n)"
        if ($createNew -eq 'y') {
            Generate-ConfigTemplate
        }
    }
}

function Open-LogDirectory {
    $logDir = Split-Path $LogFile -Parent
    if (Test-Path $logDir) {
        Write-Host "打开日志目录: $logDir" -ForegroundColor Cyan
        Start-Process explorer $logDir
    } else {
        Write-Host "日志目录不存在: $logDir" -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        Start-Process explorer $logDir
    }
}

function Show-Help {
    Show-Header
    Write-Host "使用说明:" -ForegroundColor Yellow
    Write-Host " 固定配置路径: D:\APPLY\sing-box_reF1nd" -ForegroundColor Cyan
    Write-Host " 配置文件: D:\APPLY\sing-box_reF1nd\config.json" -ForegroundColor Cyan
    Write-Host " 日志文件: D:\APPLY\sing-box_reF1nd\sing-box.log" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "运行方式:" -ForegroundColor Yellow
    Write-Host " 1. 右键点击脚本 -> 以管理员身份运行" -ForegroundColor Green
    Write-Host " 2. 使用 run-as-admin.bat 启动" -ForegroundColor Green
    Write-Host ""
    Write-Host "命令行参数:" -ForegroundColor Yellow
    Write-Host "  -Action [start|stop|restart|status]" -ForegroundColor Green
    Write-Host "  -Help                显示帮助" -ForegroundColor Green
    Write-Host ""
    Write-Host "示例:" -ForegroundColor Yellow
    Write-Host "  .\singbox-manager.ps1 -Action start" -ForegroundColor Cyan
    Write-Host "  .\singbox-manager.ps1 -Action status" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "首次使用建议:" -ForegroundColor Yellow
    Write-Host " 1. 确保 D:\APPLY\sing-box_reF1nd 目录存在" -ForegroundColor Green
    Write-Host " 2. 将 sing-box.exe 放入该目录" -ForegroundColor Green
    Write-Host " 3. 运行脚本选择 12 生成配置文件模板" -ForegroundColor Green
    Write-Host " 4. 编辑配置文件后启动" -ForegroundColor Green
    Write-Host ""
}

# 主程序
function Main {
    # 检查参数
    if ($Help) {
        Show-Help
        return
    }
    
    # 检查目录是否存在
    if (-not (Test-Path $SingBoxDir)) {
        Write-Host "sing-box 目录不存在: $SingBoxDir" -ForegroundColor Red
        Write-Host "正在创建目录..." -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $SingBoxDir -Force | Out-Null
        Write-Host "✅ 目录创建完成" -ForegroundColor Green
    }
    
    # 如果有命令行参数，直接执行
    switch ($Action.ToLower()) {
        "start" { 
            Check-Admin
            Start-SingBox
            return
        }
        "stop" { 
            Check-Admin
            Stop-SingBox
            return
        }
        "restart" { 
            Check-Admin
            Restart-SingBox
            return
        }
        "status" { 
            Get-Status
            Pause
            return
        }
    }
    
    # 交互式菜单
    do {
        Show-Menu
        $choice = Read-Host "请选择 [0-15]"
        
        switch ($choice) {
            "1" { 
                Check-Admin
                Start-SingBox
                Pause
            }
            "2" { 
                Check-Admin
                Stop-SingBox
                Pause
            }
            "3" { 
                Check-Admin
                Restart-SingBox
                Pause
            }
            "4" { 
                Get-Status
                Pause
            }
            "5" { 
                Show-Logs
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
                Install-NssmService
                Pause
            }
            "9" { 
                Uninstall-Service
                Pause
            }
            "10" { 
                Install-ScheduledTask
                Pause
            }
            "11" { 
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
            "14" { 
                Open-ConfigFile
                Pause
            }
            "15" { 
                Open-LogDirectory
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
} catch {
    Write-Host "错误: $_" -ForegroundColor Red
    Write-Host "发生在: $($_.InvocationInfo.ScriptName)" -ForegroundColor Red
    Write-Host "行号: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
    Pause
}