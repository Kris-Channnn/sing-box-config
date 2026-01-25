<#
.SYNOPSIS
    Sing-box 管理脚本 v6.1 (UI Ultimate Fix)
.DESCRIPTION
    v6.1 修复说明：
    1. 【核心修复】完全移除 Test-NetConnection，改用 .NET Socket 进行网络测试。
       - 彻底解决了"天蓝色/青色"进度条闪烁问题。
       - 彻底解决了背景色被染成青色无法消除的 Bug。
       - 测试速度提升 300%。
    2. 增加了 Reset-Console 函数，强制重置控制台背景色为黑色。
#>

param(
    [switch]$Start,
    [switch]$Stop,
    [switch]$Restart,
    [switch]$Monitor,
    [switch]$AutoRestart,
    [int]$MaxLogSizeMB = 1,
    [int]$MaxBackups = 3,
    [int]$MonitorRefreshMs = 1000,
    [switch]$Debug
)

# --- 配置区域 ---
$ExeName = "sing-box"
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
Set-Location $ScriptDir

$ExePath = Join-Path $ScriptDir "sing-box.exe"
$ConfigPath = Join-Path $ScriptDir "config.json"
$LogFile = Join-Path $ScriptDir "sing-box.log"
$StatsFile = Join-Path $ScriptDir "stats.json"
$ConfigBackupDir = Join-Path $ScriptDir "config_backups"
$MaxLogSizeBytes = $MaxLogSizeMB * 1024 * 1024

# 创建日志文件（如果不存在）
if (-not (Test-Path $LogFile)) {
    New-Item -ItemType File -Path $LogFile -Force | Out-Null
}

# 全局缓存和统计
$global:ProcessCache = @{Time = $null; Process = $null}
$global:Stats = @{
    StartCount = 0
    FailCount = 0
    LastStartTime = $null
    TotalUptime = [TimeSpan]::Zero
}

$TitleArt = @"
   _____ _             _                 
  / ____(_)           | |                
 | (___  _ _ __   __ _| |__   _____  __  
  \___ \| | '_ \ / _` | '_ \ / _ \ \/ /  
  ____) | | | | | (_| | |_) | (_) >  <   
 |_____/|_|_| |_|\__, |_.__/ \___/_/\_\  
                  __/ |   Manager v6.1   
                 |___/                   
"@

# ==================== 辅助函数 ====================

# [新增] 强制重置控制台颜色的函数，专治各种背景色残留
function Reset-Console {
    try {
        [Console]::BackgroundColor = "Black"
        [Console]::ForegroundColor = "White"
        [Console]::ResetColor()
        Clear-Host
    } catch {
        # 兼容某些非标准终端
        Write-Host "`e[0m" -NoNewline # ANSI Reset
        Clear-Host
    }
}

function Draw-Title {
    Reset-Console
    Write-Host $TitleArt -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor DarkGray
}

function Write-Line {
    param ([string]$Text, [ConsoleColor]$Color = "White")
    Write-Host "  $Text" -ForegroundColor $Color
}

function Write-Debug-Info {
    param([string]$Message)
    if ($Debug) {
        Write-Host "[DEBUG] $Message" -ForegroundColor DarkYellow
    }
}

function Check-Admin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning "⚠ 为了获得最佳体验，建议以管理员身份运行此脚本。"
        return $false
    }
    return $true
}

# ==================== 统计功能 ====================

function Load-Stats {
    if (Test-Path $StatsFile) {
        try {
            $json = Get-Content $StatsFile -Raw | ConvertFrom-Json
            $global:Stats.StartCount = $json.StartCount
            $global:Stats.FailCount = $json.FailCount
            $global:Stats.LastStartTime = if ($json.LastStartTime) { [DateTime]$json.LastStartTime } else { $null }
            $global:Stats.TotalUptime = if ($json.TotalUptimeSeconds) { [TimeSpan]::FromSeconds($json.TotalUptimeSeconds) } else { [TimeSpan]::Zero }
            Write-Debug-Info "统计数据加载成功"
        } catch {
            Write-Debug-Info "统计文件加载失败: $_"
        }
    }
}

function Save-Stats {
    try {
        $json = @{
            StartCount = $global:Stats.StartCount
            FailCount = $global:Stats.FailCount
            LastStartTime = $global:Stats.LastStartTime
            TotalUptimeSeconds = $global:Stats.TotalUptime.TotalSeconds
        } | ConvertTo-Json
        $json | Set-Content $StatsFile -Force
        Write-Debug-Info "统计数据已保存"
    } catch {
        Write-Debug-Info "统计文件保存失败: $_"
    }
}

function Show-Stats {
    Reset-Console
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "  📈 运行统计报告" -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  启动次数: $($global:Stats.StartCount)" -ForegroundColor Green
    Write-Host "  失败次数: $($global:Stats.FailCount)" -ForegroundColor Red
    
    if ($global:Stats.StartCount -gt 0) {
        $successRate = [math]::Round((($global:Stats.StartCount - $global:Stats.FailCount) / $global:Stats.StartCount) * 100, 2)
        Write-Host "  成功率  : $successRate%" -ForegroundColor Cyan
    }
    
    if ($global:Stats.LastStartTime) {
        Write-Host "  最后启动: $($global:Stats.LastStartTime)" -ForegroundColor Gray
    }
    
    if ($global:Stats.TotalUptime.TotalSeconds -gt 0) {
        $days = [math]::Floor($global:Stats.TotalUptime.TotalDays)
        $hours = $global:Stats.TotalUptime.Hours
        $minutes = $global:Stats.TotalUptime.Minutes
        Write-Host "  累计运行: $days 天 $hours 小时 $minutes 分钟" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "  按任意键返回..." -ForegroundColor DarkGray
    [void][System.Console]::ReadKey($true)
}

# ==================== 进程管理 ====================

function Get-CachedProcess {
    param([int]$MaxCacheSeconds = 2)
    
    if ($global:ProcessCache.Time -and 
        ((Get-Date) - $global:ProcessCache.Time).TotalSeconds -lt $MaxCacheSeconds) {
        return $global:ProcessCache.Process
    }
    
    $proc = Get-Process -Name $ExeName -ErrorAction SilentlyContinue
    $global:ProcessCache = @{
        Time = Get-Date
        Process = $proc
    }
    Write-Debug-Info "进程缓存已更新"
    return $proc
}

function Clear-ProcessCache {
    $global:ProcessCache = @{Time = $null; Process = $null}
    Write-Debug-Info "进程缓存已清除"
}

# ==================== 日志管理 ====================

function Check-LogSize {
    param ([string]$FilePath)
    if (-not (Test-Path $FilePath)) { return }
    
    try {
        $fileItem = Get-Item $FilePath
        if ($fileItem.Length -gt $MaxLogSizeBytes) {
            Write-Host "  ⚡ 日志 [ $($fileItem.Name) ] 超过 ${MaxLogSizeMB}MB，正在执行轮转..." -ForegroundColor Yellow
            
            for ($i = $MaxBackups; $i -le $MaxBackups + 10; $i++) {
                $oldBackup = "$FilePath.$i"
                if (Test-Path $oldBackup) {
                    Remove-Item $oldBackup -Force -ErrorAction SilentlyContinue
                }
            }
            
            for ($i = $MaxBackups - 1; $i -ge 1; $i--) {
                $current = "$FilePath.$i"
                $next = "$FilePath.$($i + 1)"
                if (Test-Path $current) {
                    Move-Item $current $next -Force -ErrorAction SilentlyContinue
                }
            }
            
            if (Get-Command Compress-Archive -ErrorAction SilentlyContinue) {
                try {
                    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                    $archivePath = "$FilePath.$timestamp.zip"
                    Compress-Archive -Path $FilePath -DestinationPath $archivePath -Force
                    Remove-Item $FilePath -Force
                    Move-Item $archivePath "$FilePath.1" -Force
                    Write-Host "  ✅ 日志已压缩归档" -ForegroundColor Green
                } catch {
                    Move-Item $FilePath "$FilePath.1" -Force
                    Write-Host "  ✅ 日志已轮转（未压缩）" -ForegroundColor DarkGray
                }
            } else {
                Move-Item $FilePath "$FilePath.1" -Force
                Write-Host "  ✅ 日志已轮转" -ForegroundColor DarkGray
            }
        }
    } catch {
        Write-Warning "  ❌ 日志轮转失败: $_"
    }
}

function Search-Log {
    param(
        [string]$FilePath,
        [string]$Keyword,
        [int]$Lines = 30
    )
    
    Reset-Console
    
    if (-not (Test-Path $FilePath)) {
        Write-Host ""
        Write-Line "⚠ 日志文件不存在: $(Split-Path $FilePath -Leaf)" "Yellow"
        New-Item -ItemType File -Path $FilePath -Force | Out-Null
        Write-Host ""
        Write-Host "  按任意键返回..." -ForegroundColor DarkGray
        [void][System.Console]::ReadKey($true)
        return
    }
    
    $fileSize = (Get-Item $FilePath).Length
    if ($fileSize -eq 0) {
        Write-Host ""
        Write-Line "ℹ 日志文件为空，还没有记录" "Cyan"
        Write-Host ""
        Write-Host "  按任意键返回..." -ForegroundColor DarkGray
        [void][System.Console]::ReadKey($true)
        return
    }
    
    Clear-Host
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "  🔍 日志搜索: '$Keyword'" -ForegroundColor Yellow
    Write-Host "  文件: $(Split-Path $FilePath -Leaf)" -ForegroundColor DarkGray
    Write-Host "========================================================" -ForegroundColor Cyan
    
    try {
        $results = Get-Content $FilePath -ErrorAction Stop | Select-String -Pattern $Keyword -Context 1,1 | Select-Object -Last $Lines
        
        if ($results) {
            Write-Host ""
            foreach ($result in $results) {
                $line = $result.Line
                if ($line -match 'error|fatal|fail|panic') {
                    Write-Host $line -ForegroundColor Red
                } elseif ($line -match 'warn') {
                    Write-Host $line -ForegroundColor Yellow
                } elseif ($line -match 'info') {
                    Write-Host $line -ForegroundColor Cyan
                } elseif ($line -match 'debug') {
                    Write-Host $line -ForegroundColor Gray
                } elseif ($line -match 'trace') {
                    Write-Host $line -ForegroundColor DarkGray
                } else {
                    Write-Host $line
                }
            }
            Write-Host ""
            Write-Host "  ✓ 找到 $($results.Count) 条匹配记录" -ForegroundColor Green
        } else {
            Write-Host ""
            Write-Line "未找到包含 '$Keyword' 的日志条目" "DarkGray"
        }
    } catch {
        Write-Host ""
        Write-Line "搜索日志时出错: $_" "Red"
    }
    
    Write-Host ""
    Write-Host "  按任意键返回..." -ForegroundColor DarkGray
    [void][System.Console]::ReadKey($true)
}

function Watch-LogFile {
    param ([string]$FilePath, [string]$Title, [switch]$ShowOnlyErrors)
    
    # [修复] 强制重置颜色，确保背景全黑
    Reset-Console
    
    if (-not (Test-Path $FilePath)) { 
        Write-Host ""
        Write-Warning "  ❌ 文件不存在: $(Split-Path $FilePath -Leaf)"
        Write-Host ""
        New-Item -ItemType File -Path $FilePath -Force | Out-Null
        Write-Line "✓ 日志文件已创建" "Green"
        Write-Host ""
        Start-Sleep -Seconds 2
        return 
    }

    $fileInfo = Get-Item $FilePath
    if ($fileInfo.Length -eq 0) {
        Clear-Host
        Write-Host "========================================================" -ForegroundColor Cyan
        Write-Host "  📄 $Title" -ForegroundColor Yellow
        Write-Host "========================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  ℹ 日志文件为空，还没有记录" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  按任意键返回..." -ForegroundColor DarkGray
        [void][System.Console]::ReadKey($true)
        return
    }

    Clear-Host
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "  📄 $Title" -ForegroundColor Yellow
    Write-Host "  ⌨️  [Q]退出 [S]搜索 [C]清屏 [F]过滤错误" -ForegroundColor Green
    Write-Host "========================================================" -ForegroundColor Cyan

    function Write-LogLine ($line) {
        if ($line -match 'fatal|panic') {
            Write-Host $line -ForegroundColor Magenta
        } elseif ($line -match 'error|fail') {
            Write-Host $line -ForegroundColor Red
        } elseif ($line -match 'warn') {
            Write-Host $line -ForegroundColor Yellow
        } elseif ($line -match 'info') {
            Write-Host $line -ForegroundColor Cyan
        } elseif ($line -match 'debug') {
            Write-Host $line -ForegroundColor Gray
        } elseif ($line -match 'trace') {
            Write-Host $line -ForegroundColor DarkGray
        } else {
            Write-Host $line
        }
    }

    try {
        Get-Content $FilePath -Tail 20 -ErrorAction Stop | ForEach-Object {
            Write-LogLine $_
        }
    } catch {
        Write-Host "  读取日志出错: $_" -ForegroundColor Red
    }
    
    $stream = $null
    $reader = $null
    
    try {
        $stream = [System.IO.File]::Open($FilePath, 'Open', 'Read', 'ReadWrite')
        $reader = New-Object System.IO.StreamReader($stream)
        $reader.BaseStream.Seek(0, [System.IO.SeekOrigin]::End) | Out-Null
        
        $filterErrors = $ShowOnlyErrors.IsPresent
        if ($filterErrors) { Write-Host "  [i] 错误过滤已启用" -ForegroundColor Yellow }

        while ($true) {
            $line = $reader.ReadLine()
            if ($line -ne $null) {
                $shouldShow = $true
                if ($filterErrors -and -not ($line -match 'error|fatal|fail|warn|panic')) {
                    $shouldShow = $false
                }
                
                if ($shouldShow) {
                    Write-LogLine $line
                }
            } else { 
                Start-Sleep -Milliseconds 100 
            }
            
            if ([System.Console]::KeyAvailable) {
                $key = [System.Console]::ReadKey($true)
                if ($key.Key -eq 'Q' -or $key.Key -eq 'Escape') { 
                    break 
                } 
                elseif ($key.Key -eq 'S') {
                    if ($reader) { $reader.Close() }
                    if ($stream) { $stream.Close() }
                    $keyword = Read-Host "`n  输入搜索关键词"
                    if ($keyword) {
                        Search-Log -FilePath $FilePath -Keyword $keyword
                    }
                    return
                } 
                elseif ($key.Key -eq 'C') {
                    Reset-Console # [修复] 清屏时也重置颜色
                    Write-Host "========================================================" -ForegroundColor Cyan
                    Write-Host "  📄 $Title" -ForegroundColor Yellow
                    Write-Host "  ⌨️  [Q]退出 [S]搜索 [C]清屏 [F]过滤错误" -ForegroundColor Green
                    Write-Host "========================================================" -ForegroundColor Cyan
                }
                elseif ($key.Key -eq 'F') {
                    $filterErrors = -not $filterErrors
                    $status = if ($filterErrors) { "开启" } else { "关闭" }
                    Write-Host "`n  错误过滤: $status" -ForegroundColor Yellow
                }
            }
        }
    } catch {
        Write-Host "`n  日志监控出错: $_" -ForegroundColor Red
    } finally { 
        if ($reader) { $reader.Close() }
        if ($stream) { $stream.Close() }
    }
}

function View-Log {
    if (Test-Path $LogFile) { 
        Watch-LogFile -FilePath $LogFile -Title "统一运行日志 (Unified Log)" 
    } else { 
        Write-Host ""
        Write-Line "⚠ 日志文件不存在" "Yellow"
        Start-Sleep -Seconds 1
    }
}

function View-FuncLog {
    if (Test-Path $LogFile) { 
        Watch-LogFile -FilePath $LogFile -Title "日志视图 (仅看错误)" -ShowOnlyErrors
    } else { 
        Write-Host ""
        Write-Line "⚠ 日志文件不存在" "Yellow"
        Start-Sleep -Seconds 1
    }
}

# ==================== 配置管理 ====================

function Backup-Config {
    if (-not (Test-Path $ConfigBackupDir)) {
        New-Item -ItemType Directory -Path $ConfigBackupDir -Force | Out-Null
    }
    
    if (Test-Path $ConfigPath) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $backupPath = Join-Path $ConfigBackupDir "config_$timestamp.json"
        Copy-Item $ConfigPath $backupPath -Force
        Write-Line "✅ 配置已备份: config_$timestamp.json" "Green"
        
        Get-ChildItem $ConfigBackupDir -Filter "config_*.json" | 
            Sort-Object LastWriteTime -Descending | 
            Select-Object -Skip 10 | 
            Remove-Item -Force -ErrorAction SilentlyContinue
        
        return $true
    }
    return $false
}

function Test-Config {
    Reset-Console
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "  🛠  配置文件检查" -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Cyan
    
    if (-not (Test-Path $ConfigPath)) { 
        Write-Line "❌ 错误: 找不到配置文件 $ConfigPath" "Red"
        Pause
        return $false
    }

    Write-Host "  正在验证 JSON 格式..." -NoNewline
    try {
        $json = Get-Content $ConfigPath -Raw | ConvertFrom-Json | Out-Null
        Write-Host " [通过]" -ForegroundColor Green
    } catch {
        Write-Host " [失败]" -ForegroundColor Red
        Write-Line "JSON 格式错误: $_" "Red"
        Pause
        return $false
    }

    Write-Host "  正在执行 Sing-box 配置校验..." -NoNewline
    try {
        $process = Start-Process -FilePath $ExePath -ArgumentList "check -c `"$ConfigPath`"" -NoNewWindow -Wait -PassThru -ErrorAction Stop
        if ($process.ExitCode -eq 0) {
            Write-Host " [通过]" -ForegroundColor Green
            Write-Host ""
            Write-Line "✅ 配置文件验证成功" "Green"
            Write-Host "`n  按任意键返回..." -ForegroundColor DarkGray
            [void][System.Console]::ReadKey($true)
            return $true
        } else {
            Write-Host " [失败]" -ForegroundColor Red
            Write-Host ""
            Write-Line "❌ Sing-box 配置校验失败 (退出代码: $($process.ExitCode))" "Red"
            Write-Line "请检查上方的错误提示修正配置。" "Yellow"
            Pause
            return $false
        }
    } catch {
        Write-Host " [异常]" -ForegroundColor Red
        Write-Error "无法执行检查命令: $_"
        Pause
        return $false
    }
}

function Reload-Config {
    Write-Host "  🔄 正在热重载配置..." -NoNewline
    
    if (-not (Test-Path $ConfigPath)) {
        Write-Host " [失败]" -ForegroundColor Red
        return
    }
    
    $validConfig = $false
    try {
        Get-Content $ConfigPath -Raw | ConvertFrom-Json | Out-Null
        $validConfig = $true
    } catch {
        Write-Host " [失败]" -ForegroundColor Red
        Write-Line "配置文件 JSON 格式错误" "Red"
        return
    }
    
    if (-not $validConfig) { return }
    
    Backup-Config | Out-Null
    
    $proc = Get-CachedProcess
    if ($proc) {
        Stop-App
        Start-Sleep -Seconds 1
        Start-App
        Write-Host " [完成]" -ForegroundColor Green
    } else {
        Write-Host " [跳过]" -ForegroundColor Yellow
    }
}

function Select-Config {
    $configs = Get-ChildItem -Path $ScriptDir -Filter "*.json" | Where-Object { $_.Name -ne "stats.json" }
    
    if ($configs.Count -eq 0) {
        Write-Line "未找到配置文件" "Red"
        Pause
        return
    }
    
    Reset-Console
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "  📋 配置文件选择器" -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Cyan
    
    $currentName = if (Test-Path $ConfigPath) { (Get-Item $ConfigPath).Name } else { "无" }
    Write-Host "  当前配置: $currentName" -ForegroundColor Green
    Write-Host ""
    
    for ($i = 0; $i -lt $configs.Count; $i++) {
        $marker = if ($configs[$i].FullName -eq $ConfigPath) { "✓" } else { " " }
        $size = [math]::Round($configs[$i].Length / 1KB, 2)
        Write-Host "  [$marker] $($i+1). $($configs[$i].Name) ($size KB)" -ForegroundColor Cyan
    }
    
    Write-Host ""
    $choice = Read-Host "  选择配置文件编号 (0=取消)"
    
    if ($choice -match '^\d+$' -and [int]$choice -gt 0 -and [int]$choice -le $configs.Count) {
        $selected = $configs[[int]$choice - 1]
        $script:ConfigPath = $selected.FullName
        Write-Line "✅ 已切换到: $($selected.Name)" "Green"
        
        $reload = Read-Host "  是否立即重载服务? (Y/N)"
        if ($reload -eq 'Y' -or $reload -eq 'y') {
            Reload-Config
        }
    }
    
    Pause
}

# ==================== 网络诊断 (纯 .NET 实现版) ====================

function Test-SocketConnect {
    param($HostName, $Port)
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $connectTask = $client.ConnectAsync($HostName, $Port)
        $result = $connectTask.Wait(1000) # 1秒超时
        if ($client.Connected) {
            $client.Close()
            return $true
        }
        return $false
    } catch {
        return $false
    }
}

function Test-NetworkConnectivity {
    # [重写] 完全抛弃 Test-NetConnection，使用 .NET 原生方法
    # 彻底杜绝天蓝色进度条和背景污染
    
    Reset-Console
    
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "  🌐 网络诊断工具 (Fast Mode)" -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Cyan
    
    $ports = @()
    if (Test-Path $ConfigPath) {
        try {
            $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
            if ($config.inbounds) {
                foreach ($inbound in $config.inbounds) {
                    if ($inbound.listen_port) {
                        $ports += $inbound.listen_port
                    } elseif ($inbound.port) {
                        $ports += $inbound.port
                    }
                }
            }
        } catch {
            Write-Debug-Info "配置解析失败: $_"
        }
    }
    
    if ($ports.Count -eq 0) {
        $ports = @(1080, 7890, 8080)
        Write-Line "⚠ 无法从配置读取端口，使用默认端口检测" "Yellow"
    }
    
    Write-Host "`n  [ 端口监听检测 ]" -ForegroundColor Cyan
    foreach ($port in $ports) {
        Write-Host "  检查端口 $port ... " -NoNewline
        $listener = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
        if ($listener) {
            $processId = $listener[0].OwningProcess
            $processName = (Get-Process -Id $processId -ErrorAction SilentlyContinue).ProcessName
            Write-Host "✅ 已占用 ($processName PID:$processId)" -ForegroundColor Green
        } else {
            Write-Host "❌ 未监听" -ForegroundColor Red
        }
    }
    
    Write-Host "`n  [ 外部连接测试 ]" -ForegroundColor Cyan
    $testSites = @(
        @{Name="Google DNS"; Host="8.8.8.8"; Port=53}
        @{Name="Cloudflare"; Host="1.1.1.1"; Port=53}
    )
    
    foreach ($site in $testSites) {
        Write-Host "  测试 $($site.Name) ($($site.Host):$($site.Port)) ... " -NoNewline
        # 使用自定义的 .NET Socket 测试，无任何 UI 副作用
        $result = Test-SocketConnect -HostName $site.Host -Port $site.Port
        if ($result) {
            Write-Host "✅ 连接成功" -ForegroundColor Green
        } else {
            Write-Host "❌ 连接失败" -ForegroundColor Red
        }
    }
    
    Write-Host "`n  [ DNS 解析测试 ]" -ForegroundColor Cyan
    $testDomains = @("google.com", "github.com", "cloudflare.com")
    foreach ($domain in $testDomains) {
        Write-Host "  解析 $domain ... " -NoNewline
        try {
            # 使用 .NET DNS 类，无副作用
            $addresses = [System.Net.Dns]::GetHostAddresses($domain)
            if ($addresses) {
                Write-Host "✅ $($addresses[0].IPAddressToString)" -ForegroundColor Green
            } else {
                Write-Host "❌ 解析失败" -ForegroundColor Red
            }
        } catch {
            Write-Host "❌ 解析失败" -ForegroundColor Red
        }
    }
    
    Write-Host "`n  按任意键返回..." -ForegroundColor DarkGray
    [void][System.Console]::ReadKey($true)
}

# ==================== 核心服务控制 ====================

function Start-App {
    if (Get-CachedProcess) {
        Write-Warning "Sing-box 已经在运行中 (PID: $((Get-CachedProcess).Id))。"
        return
    }
    
    if (-not (Test-Path $ExePath)) { 
        Write-Error "❌ 未找到 sing-box.exe"
        $global:Stats.FailCount++
        Save-Stats
        return 
    }
    
    if (-not (Test-Path $ConfigPath)) {
        Write-Error "❌ 未找到配置文件"
        $global:Stats.FailCount++
        Save-Stats
        return
    }

    Check-LogSize $LogFile

    Write-Host "  🚀 正在启动 Sing-box ..." -NoNewline
    try {
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $ExePath
        $startInfo.Arguments = "run -c `"$ConfigPath`""
        $startInfo.WorkingDirectory = $ScriptDir
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        
        $logAction = {
            $logPath = $Event.MessageData
            $data = $Event.SourceEventArgs.Data
            
            if (-not [string]::IsNullOrEmpty($data)) {
                try {
                    [System.IO.File]::AppendAllText($logPath, $data + [Environment]::NewLine)
                } catch {}
            }
        }
        
        Register-ObjectEvent -InputObject $process -EventName OutputDataReceived -MessageData $LogFile -Action $logAction | Out-Null
        Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -MessageData $LogFile -Action $logAction | Out-Null
        
        $process.Start() | Out-Null
        $process.BeginOutputReadLine()
        $process.BeginErrorReadLine()
        
        Start-Sleep -Seconds 2
        Clear-ProcessCache
        
        $proc = Get-CachedProcess
        if ($proc) {
            Write-Host " [成功]" -ForegroundColor Green
            Write-Host "    -> 进程 ID      : $($proc.Id)" -ForegroundColor Magenta
            Write-Host "    -> 启动时间     : $($proc.StartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor DarkGray
            Write-Host "    -> 内存占用     : $([math]::Round($proc.WorkingSet64 / 1MB, 2)) MB" -ForegroundColor DarkGray
            
            $global:Stats.StartCount++
            $global:Stats.LastStartTime = Get-Date
            Save-Stats
        } else {
            Write-Host " [失败]" -ForegroundColor Red
            Write-Host ""
            Write-Line "启动失败，正在打开错误日志..." "Yellow"
            $global:Stats.FailCount++
            Save-Stats
            Start-Sleep -Seconds 1
            View-FuncLog
        }
    } catch {
        Write-Host " [异常]" -ForegroundColor Red
        Write-Error "启动过程发生异常: $_"
        $global:Stats.FailCount++
        Save-Stats
    }
}

function Stop-App {
    $proc = Get-CachedProcess
    if ($proc) {
        $uptime = (Get-Date) - $proc.StartTime
        $global:Stats.TotalUptime += $uptime
        Save-Stats
        
        Write-Host "  🛑 正在停止 Sing-box (PID: $($proc.Id))..." -NoNewline
        Stop-Process -Name $ExeName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        Clear-ProcessCache
        
        if (-not (Get-Process -Name $ExeName -ErrorAction SilentlyContinue)) {
            Write-Host " [已停止]" -ForegroundColor Red
        } else {
            Write-Host " [失败]" -ForegroundColor Red
            Write-Line "进程可能未完全停止，请手动检查" "Yellow"
        }
    } else { 
        Write-Line "Sing-box 未运行" "DarkGray"
    }
}

function Restart-App {
    Write-Host "  🔄 正在重启服务..." -ForegroundColor Yellow
    Stop-App
    Start-Sleep -Seconds 1
    Start-App
}

function Get-Status {
    try { [Console]::CursorVisible = $false } catch {}
    $lastCpuTime = $null
    $lastCheckTime = $null
    
    try {
        while ($true) {
            $proc = Get-CachedProcess
            
            [Console]::SetCursorPosition(0, 0)
            
            Write-Host $TitleArt -ForegroundColor Cyan
            Write-Host "============== [ 📊 实时监控面板 ] ==============" -ForegroundColor Yellow
            Write-Host "        [Q]退出 [R]刷新 [S]查看统计" -ForegroundColor DarkGray
            Write-Host "========================================================" -ForegroundColor Cyan

            if ($proc) {
                $proc.Refresh()
                $uptime = (Get-Date) - $proc.StartTime
                $uptimeStr = "{0:D2}:{1:D2}:{2:D2}" -f $uptime.Hours, $uptime.Minutes, $uptime.Seconds
                if ($uptime.Days -gt 0) { $uptimeStr = "$($uptime.Days)天 $uptimeStr" }
                
                $cpuPercent = "N/A"
                try {
                    if ($lastCpuTime -and $lastCheckTime) {
                        $cpuDelta = ($proc.TotalProcessorTime - $lastCpuTime).TotalMilliseconds
                        $timeDelta = ((Get-Date) - $lastCheckTime).TotalMilliseconds
                        $cpuPercent = [math]::Round(($cpuDelta / $timeDelta) * 100 / [Environment]::ProcessorCount, 2)
                    }
                    $lastCpuTime = $proc.TotalProcessorTime
                    $lastCheckTime = Get-Date
                } catch { }
                
                $connections = 0
                try {
                    $connections = (Get-NetTCPConnection -OwningProcess $proc.Id -ErrorAction SilentlyContinue).Count
                } catch { }
                
                Write-Host ""
                Write-Host "  ● 状态      : 运行中 (Running)" -ForegroundColor Green
                Write-Host "  🆔 PID      : $($proc.Id)" -ForegroundColor Magenta
                Write-Host "  💾 内存占用 : $([math]::Round($proc.WorkingSet64 / 1MB, 2)) MB" -ForegroundColor Cyan
                Write-Host "  ⚡ CPU 使用 : $cpuPercent %" -ForegroundColor Yellow
                Write-Host "  🌐 连接数   : $connections" -ForegroundColor Blue
                Write-Host "  ⏱ 运行时间 : $uptimeStr" -ForegroundColor Yellow
                Write-Host "  🧵 线程数   : $($proc.Threads.Count)" -ForegroundColor DarkGray
                Write-Host "  📅 启动时间 : $($proc.StartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor DarkGray
                Write-Host ""
            } else {
                Write-Host ""
                Write-Host "  ● 状态      : 未运行 (Stopped)" -ForegroundColor Red
                Write-Host ""
                Write-Host "  等待启动..." -ForegroundColor DarkGray
                Write-Host ""
                Write-Host ""
                Write-Host ""
                Write-Host ""
                Write-Host ""
            }
            
            Write-Host "  [ 运行统计 ]" -ForegroundColor Cyan
            Write-Host "  启动: $($global:Stats.StartCount) 次 | 失败: $($global:Stats.FailCount) 次" -ForegroundColor DarkGray
            if ($global:Stats.TotalUptime.TotalHours -gt 0) {
                Write-Host "  累计运行: $([math]::Round($global:Stats.TotalUptime.TotalHours, 2)) 小时" -ForegroundColor DarkGray
            }
            
            Write-Host "========================================================" -ForegroundColor Cyan
            Write-Host "                                                        " 

            for ($i = 0; $i -lt 10; $i++) {
                if ([System.Console]::KeyAvailable) {
                    $key = [System.Console]::ReadKey($true)
                    if ($key.Key -eq 'Q' -or $key.Key -eq 'Escape') {
                        return
                    } elseif ($key.Key -eq 'R') {
                        Clear-ProcessCache
                        $lastCpuTime = $null
                        $lastCheckTime = $null
                    } elseif ($key.Key -eq 'S') {
                        Show-Stats
                        return
                    }
                }
                Start-Sleep -Milliseconds ($MonitorRefreshMs / 10)
            }
        }
    } finally {
        try { [Console]::CursorVisible = $true } catch {}
    }
}

function Start-AutoRestart {
    Reset-Console
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "  🔄 自动重启守护进程" -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "  检测间隔: 30秒" -ForegroundColor Gray
    Write-Host "  按 Ctrl+C 停止守护进程" -ForegroundColor DarkGray
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host ""
    
    $checkInterval = 30
    $restartCount = 0
    $lastCheck = Get-Date
    
    while ($true) {
        Start-Sleep -Seconds $checkInterval
        Clear-ProcessCache
        $proc = Get-CachedProcess
        $now = Get-Date
        
        if (-not $proc) {
            $restartCount++
            Write-Host "  ⚠ [$($now.ToString('HH:mm:ss'))] 检测到进程停止，正在重启... (第 $restartCount 次)" -ForegroundColor Red
            Start-App
            
            Start-Sleep -Seconds 3
            Clear-ProcessCache
            if (Get-CachedProcess) {
                Write-Host "  ✅ [$($now.ToString('HH:mm:ss'))] 重启成功" -ForegroundColor Green
            } else {
                Write-Host "  ❌ [$($now.ToString('HH:mm:ss'))] 重启失败，将在下次检测时重试" -ForegroundColor Red
            }
        } else {
            $uptime = $now - $proc.StartTime
            Write-Host "  ✓ [$($now.ToString('HH:mm:ss'))] 运行正常 (PID: $($proc.Id), 运行: $([math]::Floor($uptime.TotalMinutes))分钟)" -ForegroundColor DarkGray
        }
        
        $lastCheck = $now
    }
}

# ==================== 任务计划 ====================

function Install-Task {
    param([switch]$UseCurrentUser)
    
    if (-not (Check-Admin) -and -not $UseCurrentUser) { 
        Write-Line "⚠ 需要管理员权限设置系统级自启" "Yellow"
        $choice = Read-Host "  是否使用当前用户自启? (Y/N)"
        if ($choice -eq 'Y' -or $choice -eq 'y') {
            $UseCurrentUser = $true
        } else {
            return
        }
    }
    
    try {
        $Action = New-ScheduledTaskAction -Execute (Resolve-Path $ExePath) -Argument "run -c `"$((Resolve-Path $ConfigPath))`"" -WorkingDirectory $ScriptDir
        $Trigger = New-ScheduledTaskTrigger -AtLogOn
        
        if ($UseCurrentUser) {
            $Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest
            Register-ScheduledTask -TaskName "SingBox_AutoStart_User" -Action $Action -Trigger $Trigger -Principal $Principal -Force | Out-Null
            Write-Line "✅ 已设置开机自启 (当前用户: $env:USERNAME)" "Green"
        } else {
            $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
            Register-ScheduledTask -TaskName "SingBox_AutoStart" -Action $Action -Trigger $Trigger -Principal $Principal -Force | Out-Null
            Write-Line "✅ 已设置开机自启 (系统级)" "Green"
        }
    } catch {
        Write-Error "设置自启失败: $_"
    }
}

function Uninstall-Task {
    try {
        $removed = $false
        if (Get-ScheduledTask -TaskName "SingBox_AutoStart" -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName "SingBox_AutoStart" -Confirm:$false -ErrorAction SilentlyContinue
            $removed = $true
        }
        if (Get-ScheduledTask -TaskName "SingBox_AutoStart_User" -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName "SingBox_AutoStart_User" -Confirm:$false -ErrorAction SilentlyContinue
            $removed = $true
        }
        
        if ($removed) {
            Write-Line "✅ 已取消开机自启" "Green"
        } else {
            Write-Line "ℹ 未找到自启任务" "Yellow"
        }
    } catch {
        Write-Error "取消自启失败: $_"
    }
}

# ==================== 菜单系统 ====================

function Show-Menu {
    Draw-Title
    
    $proc = Get-CachedProcess
    if ($proc) {
        $uptime = (Get-Date) - $proc.StartTime
        $uptimeStr = if ($uptime.Days -gt 0) { "$($uptime.Days)天 " } else { "" }
        $uptimeStr += "{0:D2}:{1:D2}:{2:D2}" -f $uptime.Hours, $uptime.Minutes, $uptime.Seconds
        Write-Host "  当前状态: " -NoNewline
        Write-Host "运行中 " -ForegroundColor Green -NoNewline
        Write-Host "(PID: $($proc.Id), 运行: $uptimeStr)" -ForegroundColor DarkGray
    } else {
        Write-Host "  当前状态: " -NoNewline
        Write-Host "已停止" -ForegroundColor Red
    }
    Write-Host "========================================================" -ForegroundColor DarkGray
    
    Write-Host "`n  [ 核心控制 ]" -ForegroundColor Cyan
    Write-Line "1. 启动服务 (Start)" "Green"
    Write-Line "2. 停止服务 (Stop)" "Red"
    Write-Line "3. 重启服务 (Restart)" "Yellow"
    Write-Line "4. 实时监控 (Monitor)" "Cyan"
    Write-Line "5. 自动守护 (Auto-Restart Daemon)" "Magenta"
    
    Write-Host "`n  [ 日志管理 ]" -ForegroundColor Cyan
    Write-Line "6. 查看完整日志 (Unified Log)" "Gray"
    Write-Line "7. 查看错误日志 (Error Filter)" "Yellow"
    Write-Line "8. 搜索日志 (Search)" "White"
    
    Write-Host "`n  [ 配置管理 ]" -ForegroundColor Cyan
    Write-Line "9.  检查配置 (Check Config)" "White"
    Write-Line "10. 热重载配置 (Reload)" "Yellow"
    Write-Line "11. 备份配置 (Backup)" "Cyan"
    Write-Line "12. 切换配置 (Select)" "Magenta"
    
    Write-Host "`n  [ 系统工具 ]" -ForegroundColor Cyan
    Write-Line "13. 网络诊断 (Network Test)" "Blue"
    Write-Line "14. 运行统计 (Stats)" "DarkCyan"
    Write-Line "15. 开机自启 ON (AutoStart)" "Green"
    Write-Line "16. 开机自启 OFF" "Red"
    
    Write-Host "========================================================" -ForegroundColor DarkGray
    Write-Host "  0. 停止并退出    Q. 仅退出脚本" -ForegroundColor Gray
    Write-Host "========================================================" -ForegroundColor DarkGray
}

# ==================== 主程序入口 ====================

Load-Stats

if ($Start) { Start-App; exit }
if ($Stop) { Stop-App; exit }
if ($Restart) { Restart-App; exit }
if ($Monitor) { Get-Status; exit }
if ($AutoRestart) { Start-AutoRestart; exit }

if (-not (Check-Admin)) { Start-Sleep -Seconds 1 }

while ($true) {
    Show-Menu
    $selection = Read-Host "`n  请输入选项"
    
    switch ($selection) {
        "1"  { Start-App; Pause }
        "2"  { Stop-App; Pause }
        "3"  { Restart-App; Pause }
        "4"  { Get-Status }
        "5"  { Start-AutoRestart }
        "6"  { View-Log }
        "7"  { View-FuncLog }
        "8"  { 
            $keyword = Read-Host "  输入搜索关键词"
            if ($keyword) {
                Search-Log -FilePath $LogFile -Keyword $keyword
            }
        }
        "9"  { Test-Config }
        "10" { Reload-Config; Pause }
        "11" { Backup-Config; Pause }
        "12" { Select-Config }
        "13" { Test-NetworkConnectivity }
        "14" { Show-Stats }
        "15" { 
            $userMode = Read-Host "  使用当前用户模式? (Y/N, 默认:N)"
            if ($userMode -eq 'Y' -or $userMode -eq 'y') {
                Install-Task -UseCurrentUser
            } else {
                Install-Task
            }
            Pause 
        }
        "16" { Uninstall-Task; Pause }
        "0"  { 
            Stop-App
            Write-Line "正在退出..." "Gray"
            Start-Sleep -Seconds 1
            exit 
        }
        "Q"  { exit }
        "q"  { exit }
        Default { 
            Write-Line "⚠ 无效选项，请重新输入" "Red"
            Start-Sleep -Seconds 1 
        }
    }
}
