<#
.SYNOPSIS
    Sing-box Manager (WinSW Edition) v8.3 Revised
.DESCRIPTION
    v8.3 更新日志：
    1. [交互] 全面引入 Esc 键返回机制，子菜单操作更加流畅。
    2. [核心] 新增 Read-Choice 函数，实现无回车菜单选择。
    3. [网络] 保持 v8.2 的 Socket 异步网络诊断。
    4. [日志] 保持 v8.2 的日志搜索与归档功能。
#>

param(
    [switch]$Start,
    [switch]$Stop,
    [switch]$Restart,
    [switch]$Monitor,
    [int]$MonitorRefreshMs = 1000
)

# ==================== 0. 视觉优化 ====================
try {
    $psWindow = (Get-Host).UI.RawUI
    $newSize = $psWindow.WindowSize
    $newSize.Width = 130
    $newSize.Height = 40
    $psWindow.WindowSize = $newSize
    $bufferSize = $psWindow.BufferSize
    $bufferSize.Width = 130
    $bufferSize.Height = 2000
    $psWindow.BufferSize = $bufferSize
} catch {}

# ==================== 全局配置 ====================
$ErrorActionPreference = "SilentlyContinue"
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
Set-Location $ScriptDir

# 核心定义
$ExeName      = "sing-box"
$ServiceBase  = "singbox-service" 
$ServiceName  = "Sing-box-Service"
$ServiceTitle = "Sing-box Core Service"

# 路径定义
$SingBoxPath  = Join-Path $ScriptDir "$ExeName.exe"
$ConfigPath   = Join-Path $ScriptDir "config.json"
$ServiceExe   = Join-Path $ScriptDir "$ServiceBase.exe"
$ServiceXml   = Join-Path $ScriptDir "$ServiceBase.xml"
$LogFile      = Join-Path $ScriptDir "$ServiceBase.err.log" 
$PidFile      = Join-Path $ScriptDir "service.pid"
$ConfigBackupDir = Join-Path $ScriptDir "config_backups"
$LogArchiveDir   = Join-Path $ScriptDir "log_archives"
$ConfigNameFile  = Join-Path $ScriptDir ".current_config_name"
$WinSWUrl     = "https://github.com/winsw/winsw/releases/download/v2.12.0/WinSW.NET461.exe"
$TaskName     = "SingBox_Delayed_Start"

$TitleArt = @"
   _____ _             _                 
  / ____(_)           | |                
 | (___  _ _ __   __ _| |__   _____  __  
  \___ \| | '_ \ / _` | '_ \ / _ \ \/ /  
  ____) | | | | | (_| | |_) | (_) >  <   
 |_____/|_|_| |_|\__, |_.__/ \___/_/\_\  
                  __/ |   Sing-box Manager
                 |___/    v8.3 (Service) 
"@

# ==================== 基础工具函数 ====================

function Reset-Console {
    try {
        [Console]::BackgroundColor = "Black"
        [Console]::ForegroundColor = "White"
        [Console]::ResetColor()
        Clear-Host
    } catch { Clear-Host }
}

function Write-Line {
    param ([string]$Text, [ConsoleColor]$Color = "White")
    Write-Host "  $Text" -ForegroundColor $Color
}

function Wait-Key {
    param([string]$Msg = "按任意键返回 (Esc 退出)...")
    Write-Host "`n  $Msg" -ForegroundColor DarkGray
    while ($true) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq "Escape") { return "Escape" }
            return "Any"
        }
        Start-Sleep -Milliseconds 50
    }
}

# [新增] 专门用于菜单选择，支持 Esc 瞬间返回
function Read-Choice {
    param([string[]]$ValidKeys)
    while ($true) {
        if ([Console]::KeyAvailable) {
            $k = [Console]::ReadKey($true)
            if ($k.Key -eq "Escape") { return "Escape" }
            foreach ($vk in $ValidKeys) {
                if ($k.KeyChar.ToString().ToLower() -eq $vk.ToLower()) { return $vk }
            }
        }
        Start-Sleep -Milliseconds 50
    }
}

function Check-Admin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Reset-Console
        Write-Host $TitleArt -ForegroundColor Cyan
        Write-Host "`n  [!] 必须以管理员身份运行此脚本。" -ForegroundColor Red
        Wait-Key | Out-Null
        exit
    }
}

# ==================== WinSW 部署 ====================

function Ensure-WinSW {
    if (-not (Test-Path $SingBoxPath)) {
        Write-Host "❌ 错误: 找不到 $ExeName.exe" -ForegroundColor Red
        exit
    }
    if (-not (Test-Path $ServiceExe)) {
        $OldServiceExe = Join-Path $ScriptDir "service.exe"
        if (Test-Path $OldServiceExe) {
            Write-Line "检测到旧版 service.exe，正在迁移..." "Yellow"
            Stop-Service-Wrapper
            Move-Item $OldServiceExe $ServiceExe -Force
            $OldXml = Join-Path $ScriptDir "service.xml"
            if (Test-Path $OldXml) { Move-Item $OldXml $ServiceXml -Force }
        } else {
            Write-Line "未找到服务宿主，正在下载 WinSW..." "Yellow"
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Invoke-WebRequest -Uri $WinSWUrl -OutFile $ServiceExe -UseBasicParsing
                Write-Line "✅ 下载完成" "Green"
            } catch {
                Write-Line "❌ 下载失败，请手动下载 WinSW 改名为 singbox-service.exe" "Red"
                exit
            }
        }
    }
    
    if (-not (Test-Path $ServiceXml)) {
        Write-Line "正在生成配置 $ServiceBase.xml ..." "Cyan"
        $xmlContent = @"
<service>
  <id>$ServiceName</id>
  <name>$ServiceTitle</name>
  <description>High-performance proxy platform (Managed by Singbox-Manager)</description>
  <executable>%BASE%\$ExeName.exe</executable>
  <arguments>run -c config.json</arguments>
  <workingdirectory>%BASE%</workingdirectory>
  <onfailure action="restart" delay="5 sec"/>
  <onfailure action="restart" delay="10 sec"/>
  <log mode="roll-by-size">
    <sizeThreshold>3072</sizeThreshold>
    <keepFiles>5</keepFiles>
  </log>
  <pidfile>%BASE%\service.pid</pidfile>
</service>
"@
        Set-Content $ServiceXml $xmlContent -Encoding UTF8
        Write-Line "✅ 配置文件已生成 (Log Limit: 3MB)" "Green"
    }
}

function Update-WinSW {
    Reset-Console
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "  ⬇️  更新 WinSW 服务内核" -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Cyan
    
    Write-Line "此操作将停止服务，下载最新 WinSW 并替换。" "Yellow"
    Write-Host "`n  确认更新? (Y/N, Esc取消)" -ForegroundColor DarkGray
    
    $c = Read-Choice -ValidKeys "y","n"
    if ($c -eq "Escape" -or $c -eq "n") { return }

    Stop-Service-Wrapper
    Start-Sleep -Seconds 1
    
    if (Test-Path $ServiceExe) { Copy-Item $ServiceExe "$ServiceExe.bak" -Force }

    Write-Line "正在从 GitHub 下载..." "Cyan"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $WinSWUrl -OutFile $ServiceExe -UseBasicParsing
        Write-Line "✅ 更新成功！" "Green"
        
        Write-Host "  是否立即启动服务? (Y/N)" -ForegroundColor DarkGray
        $restart = Read-Choice -ValidKeys "y","n"
        if ($restart -eq 'y') { Start-Service-Wrapper }
    } catch {
        Write-Line "❌ 更新失败: $_" "Red"
        if (Test-Path "$ServiceExe.bak") { Move-Item "$ServiceExe.bak" $ServiceExe -Force }
        Wait-Key | Out-Null
    }
}

# ==================== 自启管理 ====================

function Set-AutoStart {
    Reset-Console
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "  🚀 开机自启设置 (AutoStart Settings)" -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Cyan
    
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    
    Write-Host "  当前状态: " -NoNewline
    if ($task) {
        Write-Host "延迟启动任务 (Delayed Task)" -ForegroundColor Magenta
    } elseif ($svc -and $svc.StartType -eq "Automatic") {
        Write-Host "标准 Windows 自启 (Automatic)" -ForegroundColor Green
    } else {
        Write-Host "手动/已禁用 (Manual)" -ForegroundColor DarkGray
    }
    
    Write-Host "--------------------------------------------------------" -ForegroundColor DarkGray
    
    Write-Line "1. 标准自启 (Standard)" "Green"
    Write-Line "   - 随 Windows 服务自动启动 (最快)" "DarkGray"
    Write-Host ""
    Write-Line "2. 延迟启动 (Delayed Task)" "Yellow"
    Write-Line "   - 适合: PPPoE拨号、Wifi连接慢的设备" "DarkGray"
    Write-Host ""
    Write-Line "3. 禁用自启 (Manual)" "White"
    Write-Line "   - 仅在需要时手动打开脚本启动" "DarkGray"
    
    Write-Host "========================================================" -ForegroundColor DarkGray
    Write-Host "  请按数字键选择 (1-3) 或按 Esc 返回" -ForegroundColor Cyan
    
    $choice = Read-Choice -ValidKeys "1","2","3"
    if ($choice -eq "Escape") { return }
    
    switch ($choice) {
        "1" {
            Write-Line "正在配置为 [标准自启]..." "Cyan"
            if ($task) { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue }
            Set-Service -Name $ServiceName -StartupType Automatic
            Write-Line "✅ 已设置为随系统自动启动" "Green"
        }
        "2" {
            Write-Line "正在配置为 [延迟启动]..." "Cyan"
            $delay = Read-Host "  请输入开机后等待的秒数 (默认 30, 回车默认)"
            if (-not $delay -match '^\d+$') { $delay = 30 }
            
            Set-Service -Name $ServiceName -StartupType Manual
            
            $actionScript = "Start-Sleep -Seconds $delay; Start-Service '$ServiceName'"
            $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -Command `"$actionScript`""
            $trigger = New-ScheduledTaskTrigger -AtLogOn
            $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
            
            Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
            Write-Line "✅ 已创建延迟任务: 开机后等待 ${delay}秒 启动" "Green"
        }
        "3" {
            Write-Line "正在禁用自动启动..." "Cyan"
            if ($task) { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue }
            Set-Service -Name $ServiceName -StartupType Manual
            Write-Line "✅ 已禁用自启 (需手动运行)" "Green"
        }
    }
    Wait-Key | Out-Null
}

# ==================== 服务控制 ====================

function Get-ServiceState {
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($null -eq $svc) { return "NotInstalled" }
    return $svc.Status.ToString()
}

function Install-Service {
    Ensure-WinSW
    if ((Get-ServiceState) -ne "NotInstalled") { return }
    Start-Process -FilePath $ServiceExe -ArgumentList "install" -Wait -NoNewWindow
    Write-Line "✅ 服务安装成功" "Green"
}

function Start-Service-Wrapper {
    Ensure-WinSW
    Archive-Old-Logs
    $state = Get-ServiceState
    if ($state -eq "NotInstalled") { Install-Service }
    elseif ($state -eq "Running") { Write-Line "服务已在运行。" "Yellow"; return }

    Write-Line "🚀 正在启动..." "Cyan"
    Start-Process -FilePath $ServiceExe -ArgumentList "start" -Wait -NoNewWindow
    
    $retry = 0
    while ($retry -lt 10) {
        if ((Get-ServiceState) -eq "Running") {
            Write-Line "✅ 服务启动成功" "Green"
            return
        }
        Start-Sleep -Milliseconds 500
        $retry++
    }
}

function Stop-Service-Wrapper {
    if ((Get-ServiceState) -eq "Running") {
        Write-Line "🛑 正在停止..." "Red"
        Start-Process -FilePath $ServiceExe -ArgumentList "stop" -Wait -NoNewWindow
        Write-Line "✅ 服务已停止" "Green"
    } else {
        Write-Line "服务未运行。" "DarkGray"
    }
}

function Restart-Service-Wrapper {
    Stop-Service-Wrapper
    Start-Sleep -Seconds 1
    Start-Service-Wrapper
}

function Show-Restart-Menu {
    Reset-Console
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "  🔄 服务重启选项 (Restart Options)" -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Line "1. 强制重启 (Direct Restart)" "Red"
    Write-Line "   - 直接停止并重新启动服务" "DarkGray"
    Write-Host ""
    Write-Line "2. 安全重载 (Safe Reload)" "Green"
    Write-Line "   - 校验配置 -> 备份配置 -> 重启服务" "DarkGray"
    Write-Host "========================================================" -ForegroundColor DarkGray
    Write-Host "  请按数字键选择 (1-2) 或按 Esc 返回" -ForegroundColor Cyan
    
    $c = Read-Choice -ValidKeys "1","2"
    if ($c -eq "Escape") { return }

    if ($c -eq "1") {
        Restart-Service-Wrapper
    } elseif ($c -eq "2") {
        if (Check-Config-Silent) {
            Backup-Config-Wrapper
            Restart-Service-Wrapper
        } else {
            Write-Line "❌ 配置校验失败，已取消重启以保护服务。" "Red"
            Wait-Key | Out-Null
        }
    }
}

# ==================== 日志与配置管理 ====================

function Backup-Config-Wrapper {
    if (-not (Test-Path $ConfigBackupDir)) { New-Item -ItemType Directory -Path $ConfigBackupDir -Force | Out-Null }
    if (Test-Path $ConfigPath) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $backupPath = Join-Path $ConfigBackupDir "config_$timestamp.json"
        Copy-Item $ConfigPath $backupPath -Force
        Write-Line "✅ 配置已备份至: $backupPath" "Green"
        Get-ChildItem $ConfigBackupDir -Filter "config_*.json" | Sort-Object LastWriteTime -Descending | Select-Object -Skip 10 | Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

function Archive-Old-Logs {
    # 1. 基础归档根目录
    if (-not (Test-Path $LogArchiveDir)) { New-Item -ItemType Directory -Path $LogArchiveDir -Force | Out-Null }
    
    # [关键修复] 修改匹配规则
    # 旧规则: Filter "$ServiceBase.err.log.*" | Where-Object { $_.Name -match '\.\d+$' }
    # 新规则: 匹配 singbox-service.0.err.log 这种格式
    $rotatedLogs = Get-ChildItem -Path $ScriptDir -Filter "$ServiceBase.*.err.log" | Where-Object { $_.Name -match "$ServiceBase\.\d+\.err\.log$" }
    
    foreach ($log in $rotatedLogs) {
        try {
            # 尝试检测文件锁
            $stream = [System.IO.File]::Open($log.FullName, 'Open', 'ReadWrite', 'None')
            $stream.Close()
            
            # 2. 生成基于日期的子文件夹 (按月)
            $dateFolder = Get-Date -Format "yyyy-MM"
            $targetDir = Join-Path $LogArchiveDir $dateFolder
            
            if (-not (Test-Path $targetDir)) { 
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null 
            }
            
            # 3. 组合路径并压缩
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            # 为了文件名好看，把中间的数字移到后面，或者保留原名
            $zipName = "$($log.Name)_$timestamp.zip"
            $zipPath = Join-Path $targetDir $zipName
            
            Write-Host "  📦 [自动维护] 正在归档: $($log.Name) ..." -ForegroundColor Cyan
            
            Compress-Archive -Path $log.FullName -DestinationPath $zipPath -Force -ErrorAction Stop
            Remove-Item $log.FullName -Force
            Write-Host "     -> 已存入: $dateFolder\$zipName" -ForegroundColor DarkGray
            
        } catch {
            Write-Debug "文件 $($log.Name) 可能正在被写入，跳过。"
        }
    }
}

function Search-Log-Internal {
    param([string]$Keyword)
    Reset-Console
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "  🔍 日志搜索: '$Keyword' (显示最近 100 条匹配及上下文)" -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Cyan
    
    if (-not (Test-Path $LogFile)) { return }
    
    try {
        # [修改1] 将显示数量从 20 提升到 50 (Select-Object -Last 50)
        # [保留] Context 1,1 表示同时获取匹配行的 前一行 和 后一行
        $results = Get-Content $LogFile -ErrorAction Stop | Select-String -Pattern $Keyword -Context 1,1 | Select-Object -Last 100
        
        if ($results) {
            foreach ($matchItem in $results) {
                # [修改2] 显示前置上下文 (PreContext)，用深灰色显示
                if ($matchItem.Context.PreContext) {
                    foreach ($pre in $matchItem.Context.PreContext) { 
                        Write-Host "   $($pre.Trim())" -ForegroundColor DarkGray 
                    }
                }

                # 显示匹配行 (增加 >> 标记以突出显示)
                $line = $matchItem.Line.Trim()
                if ($line -match 'error|fatal|panic') { Write-Host ">> $line" -ForegroundColor Red }
                elseif ($line -match 'warn') { Write-Host ">> $line" -ForegroundColor Yellow }
                else { Write-Host ">> $line" -ForegroundColor White }

                # [修改2] 显示后置上下文 (PostContext)，用深灰色显示
                if ($matchItem.Context.PostContext) {
                    foreach ($post in $matchItem.Context.PostContext) { 
                        Write-Host "   $($post.Trim())" -ForegroundColor DarkGray 
                    }
                }
                
                # 添加分隔线，区分不同时间段的日志
                Write-Host "   ----------------" -ForegroundColor DarkGray
            }
        } else {
            Write-Host "  未找到匹配项。" -ForegroundColor DarkGray
        }
    } catch { Write-Host "搜索出错: $_" -ForegroundColor Red }
    
    Write-Host "`n  按任意键返回日志流 (Esc 退出)..." -ForegroundColor DarkGray
    Wait-Key | Out-Null
}

function View-Log {
    $filterWarn = $false
    
    function Draw-LogHeader {
        Reset-Console
        Write-Host "========================================================" -ForegroundColor Cyan
        Write-Host "  📄 service.auto.log (完整日志流)" -ForegroundColor Yellow
        $statusFilter = if ($filterWarn) { "开启" } else { "关闭" }
        Write-Host "  [F]过滤Warn($statusFilter) [C]清空 [R]重载 [S]搜索 [Esc]退出" -ForegroundColor Green
        Write-Host "========================================================" -ForegroundColor Cyan
    }

    Draw-LogHeader

    if (-not (Test-Path $LogFile)) {
        Write-Line "暂无日志文件 ($LogFile)" "Yellow"
        Wait-Key | Out-Null
        return
    }

    $reader = $null
    $stream = $null
    # [新增] 记录上次文件大小
    $lastSize = (Get-Item $LogFile).Length

    try {
        $stream = [System.IO.File]::Open($LogFile, 'Open', 'Read', 'ReadWrite')
        $reader = New-Object System.IO.StreamReader($stream)
        $reader.BaseStream.Seek(0, [System.IO.SeekOrigin]::End) | Out-Null
        
        while ($true) {
            $line = $reader.ReadLine()
            if ($line) {
                # ... (原有的日志颜色渲染逻辑) ...
                $isImportant = ($line -match "WARN|ERROR|FATAL|PANIC")
                if ($filterWarn -and -not $isImportant) { } else {
                    if ($line -match "ERROR|FATAL|panic") { Write-Host $line -ForegroundColor Red }
                    elseif ($line -match "WARN") { Write-Host $line -ForegroundColor Yellow }
                    elseif ($line -match "INFO") { Write-Host $line -ForegroundColor Cyan }
                    else { Write-Host $line }
                }
            } else {
                # 没读到新行，休息一下
                Start-Sleep -Milliseconds 100
                
                # ========== [新增] 轮转/截断检测逻辑 ==========
                try {
                    # 获取当前文件实际大小
                    $currentSize = (Get-Item $LogFile).Length
                    
                    # 如果当前大小比之前记录的小很多（说明被截断或轮转了）
                    if ($currentSize -lt $lastSize) {
                        Write-Host "`n  >>> ⚠ 检测到日志轮转或重置 (Size: $lastSize -> $currentSize) <<<" -ForegroundColor Magenta
                        Write-Host "  >>> 🔄 正在自动重载新日志流..." -ForegroundColor Magenta
                        
                        # 关闭旧流
                        $reader.Close(); $stream.Close()
                        Start-Sleep -Milliseconds 200
                        
                        # 重新打开新流
                        $stream = [System.IO.File]::Open($LogFile, 'Open', 'Read', 'ReadWrite')
                        $reader = New-Object System.IO.StreamReader($stream)
                        # 这里选择是否跳到末尾，或者从头开始。轮转后的新日志通常是空的或只有开头，从头读比较好
                        # $reader.BaseStream.Seek(0, [System.IO.SeekOrigin]::End) | Out-Null
                        
                        $lastSize = $currentSize
                        Write-Host "  >>> ✅ 重载完成，继续监控 <<<`n" -ForegroundColor DarkGray
                    } else {
                        $lastSize = $currentSize
                    }
                } catch {
                    # 文件可能被锁住瞬间无法访问，忽略
                }
                # ============================================
            }

            # ... (底部的原有按键监听代码 [F], [S], [R], [C] 等保持不变) ...
            if ([Console]::KeyAvailable) {
                $k = [Console]::ReadKey($true)
                if ($k.Key -eq "Escape") { break }
                # ... 其他按键逻辑请保留原样 ...
                # (为节省篇幅，这里省略了按键处理代码，请直接复制原脚本中的这部分)
                if ($k.Key -eq "F") { $filterWarn = -not $filterWarn; Draw-LogHeader }
                if ($k.Key -eq "S") {
                     # ... 原有搜索逻辑 ...
                     # 注意：搜索完回来记得重置 $stream, $reader 和 $lastSize
                     if ($reader) { $reader.Close() }
                     if ($stream) { $stream.Close() }
                     $kw = Read-Host "`n  请输入搜索关键词 (回车取消)"
                     if ($kw) { Search-Log-Internal -Keyword $kw }
                     Draw-LogHeader
                     try {
                        $stream = [System.IO.File]::Open($LogFile, 'Open', 'Read', 'ReadWrite')
                        $reader = New-Object System.IO.StreamReader($stream)
                        $reader.BaseStream.Seek(0, [System.IO.SeekOrigin]::End) | Out-Null
                        $lastSize = (Get-Item $LogFile).Length # 更新大小
                     } catch { break }
                }
                if ($k.Key -eq "R") { 
                    # ... 原有重载逻辑 ...
                    if ($reader) { $reader.Close() }
                    if ($stream) { $stream.Close() }
                    Start-Sleep -Milliseconds 200
                    Draw-LogHeader
                    try {
                        $stream = [System.IO.File]::Open($LogFile, 'Open', 'Read', 'ReadWrite')
                        $reader = New-Object System.IO.StreamReader($stream)
                        $reader.BaseStream.Seek(0, [System.IO.SeekOrigin]::End) | Out-Null
                        Write-Host "  ✅ 日志流已重载" -ForegroundColor Green
                        $lastSize = (Get-Item $LogFile).Length # 更新大小
                    } catch { break }
                }
                if ($k.Key -eq "C") {
                    # ... 原有清空逻辑 ...
                    if ($reader) { $reader.Close() }
                    if ($stream) { $stream.Close() }
                    try { Clear-Content $LogFile -ErrorAction Stop; Draw-LogHeader; Write-Host "  ✅ 已清空" -ForegroundColor Green } 
                    catch { Draw-LogHeader; Write-Host "  ⚠ 只能清空显示(文件被占用)" -ForegroundColor Yellow }
                    try {
                        $stream = [System.IO.File]::Open($LogFile, 'Open', 'Read', 'ReadWrite')
                        $reader = New-Object System.IO.StreamReader($stream)
                        $reader.BaseStream.Seek(0, [System.IO.SeekOrigin]::End) | Out-Null
                        $lastSize = (Get-Item $LogFile).Length # 更新大小
                    } catch {}
                }
            }
        }
    } finally {
        if ($reader) { $reader.Close() }
        if ($stream) { $stream.Close() }
    }
}

function Select-Config {
    Reset-Console
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "  ⚙️  切换配置文件 (Switch Config)" -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Cyan

    $configs = Get-ChildItem -Path $ScriptDir -Filter "*.json" | Where-Object { 
        $_.Name -ne "service.json" -and $_.Name -ne "stats.json" -and $_.Name -notmatch "singbox-service" -and $_.Name -notmatch "config_20"
    }

    if ($configs.Count -eq 0) {
        Write-Line "未找到其他 .json 配置文件" "Red"
        Wait-Key | Out-Null
        return
    }

    Write-Host "  当前配置: config.json" -ForegroundColor DarkGray
    Write-Host ""

    for ($i = 0; $i -lt $configs.Count; $i++) {
        $sizeKB = [math]::Round($configs[$i].Length / 1KB, 2)
        Write-Host "  [$($i+1)] $($configs[$i].Name)  `t($sizeKB KB)" -ForegroundColor Cyan
    }

    Write-Host ""
    $input = Read-Host "  请输入序号 (0 或直接回车返回)"
    
    if (-not $input -or $input -eq "0") { return }

    if ($input -match '^\d+$' -and [int]$input -gt 0 -and [int]$input -le $configs.Count) {
        $selected = $configs[[int]$input - 1]
        if ($selected.Name -eq "config.json") { return }  
        # [新增] 关键修改：在覆盖前强制备份当前的 config.json
        Write-Line "正在备份旧配置到 config_backups 目录..." "DarkGray"
        Backup-Config-Wrapper
        Write-Line "正在应用: $($selected.Name) -> config.json ..." "Yellow"
        try {
            Copy-Item $selected.FullName -Destination $ConfigPath -Force
            Set-Content $ConfigNameFile -Value $selected.Name -Force
            Write-Line "✅ 配置文件替换成功" "Green"
            Write-Host "  是否立即重启服务生效? (Y/N)" -ForegroundColor DarkGray
            $doRestart = Read-Choice -ValidKeys "y","n"
            if ($doRestart -eq 'y') { Restart-Service-Wrapper }
        } catch {
            Write-Line "❌ 替换失败: $_" "Red"
            Wait-Key | Out-Null
        }
    }
}

function Find-SingBoxProcess {
    if (Test-Path $PidFile) {
        try {
            $pidVal = [int](Get-Content $PidFile).Trim()
            $proc = Get-CimInstance Win32_Process -Filter "ProcessId = $pidVal" -ErrorAction SilentlyContinue
            if ($proc) { return $proc }
        } catch {}
    }
    $candidates = Get-CimInstance Win32_Process -Filter "Name = '$ExeName.exe'" -ErrorAction SilentlyContinue
    foreach ($p in $candidates) {
        if ($p.ExecutablePath -eq $SingBoxPath) { return $p }
    }
    return $null
}

function Show-Monitor {
    Reset-Console
    try { [Console]::CursorVisible = $false } catch {}
    
    # [初始化] 轮转检测变量
    $lastRotationCheck = Get-Date
    $rotationMsg = ""
    
    # [初始化] API 流量检测变量
    $apiPort = $null
    $apiSecret = ""
    
    # [初始化] 用于手动计算速度的历史变量
    $lastTotalUpBytes = 0
    $lastTotalDownBytes = 0
    $isFirstLoop = $true
    
    # 1. 尝试从配置中读取 Clash API 端口
    if (Test-Path $ConfigPath) {
        try {
            $json = Get-Content $ConfigPath -Raw | ConvertFrom-Json
            if ($json.experimental -and $json.experimental.clash_api -and $json.experimental.clash_api.external_controller) {
                $parts = $json.experimental.clash_api.external_controller -split ":"
                $apiPort = $parts[-1]
                if ($json.experimental.clash_api.secret) { $apiSecret = $json.experimental.clash_api.secret }
            }
        } catch {}
    }

    while ($true) {
        [Console]::SetCursorPosition(0, 0)
        Write-Host $TitleArt -ForegroundColor Cyan
        Write-Host "============== [ 📊 实时监控面板 ] ==============" -ForegroundColor Yellow
        Write-Host "        [Esc] 返回   [L] 完整日志   [R] 刷新" -ForegroundColor DarkGray
        Write-Host "========================================================" -ForegroundColor Cyan
        
        # ========== [功能 1] 轮转检测 (修复后的正则匹配) ==========
        if (((Get-Date) - $lastRotationCheck).TotalSeconds -gt 2) {
            # 适配 WinSW 默认的中间数字格式: *.0.err.log
            $rotated = Get-ChildItem -Path $ScriptDir -Filter "$ServiceBase.*.err.log" | Where-Object { $_.Name -match "$ServiceBase\.\d+\.err\.log$" }
            
            if ($rotated) {
                $rotationMsg = "⚠ 检测到日志已轮转! 发现 $($rotated.Count) 个旧文件待归档"
            } else { $rotationMsg = "" }
            $lastRotationCheck = Get-Date
        }

        if ($rotationMsg) {
            Write-Host "  $rotationMsg" -ForegroundColor DarkYellow
            Write-Host "--------------------------------------------------------" -ForegroundColor DarkGray
        } else {
            Write-Host "                                                        " 
            Write-Host "                                                        " 
        }

        # ========== [功能 2] 获取服务与进程信息 ==========
        $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        
        if ($svc -and $svc.Status -eq "Running") {
            $procInfo = Find-SingBoxProcess
            # 补空格擦除旧残影
            Write-Host "`n  ● 服务状态  : 正在运行 (Running)$(' ' * 20)" -ForegroundColor Green
            
            if ($procInfo) {
                # --- [修复] 运行时长计算 ---
                $startTime = $procInfo.CreationDate
                $uptimeStr = "N/A"
                if ($startTime) {
                    if ($startTime -is [string]) { try { $startTime = [Management.ManagementDateTimeConverter]::ToDateTime($startTime) } catch {} }
                    $uptime = (Get-Date) - $startTime
                    $uptimeStr = "{0:D2}:{1:D2}:{2:D2}" -f $uptime.Hours, $uptime.Minutes, $uptime.Seconds
                    if ($uptime.Days -gt 0) { $uptimeStr = "$($uptime.Days)天 $uptimeStr" }
                }

                # --- 基础进程信息 ---
                $memMB = [math]::Round($procInfo.WorkingSetSize / 1MB, 2)
                $conns = (Get-NetTCPConnection -OwningProcess $procInfo.ProcessId -State Established -ErrorAction SilentlyContinue).Count
                $logSize = "0 KB"; if (Test-Path $LogFile) { $logSize = "{0:N2} MB" -f ((Get-Item $LogFile).Length / 1MB) }

                # --- [修复] 实时流量计算 (差值法解决 API 返回 0 的问题) ---
                $speedUpStr = "0 KB/s"; $speedDownStr = "0 KB/s"
                $totalUpStr = "0 MB";   $totalDownStr = "0 MB"
                
                if ($apiPort) {
                    try {
                        $uri = "http://127.0.0.1:$apiPort/connections"
                        $headers = @{}
                        if ($apiSecret) { $headers["Authorization"] = "Bearer $apiSecret" }
                        
                        $stats = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec 1 -ErrorAction SilentlyContinue
                        
                        if ($stats) {
                            $curUp = $stats.uploadTotal
                            $curDown = $stats.downloadTotal
                            $fmtSpeed = { param($b) if ($b -gt 1MB) { "{0:N2} MB/s" -f ($b/1MB) } else { "{0:N0} KB/s" -f ($b/1KB) } }
                            $fmtTotal = { param($b) if ($b -gt 1GB) { "{0:N2} GB" -f ($b/1GB) } else { "{0:N2} MB" -f ($b/1MB) } }
                            
                            if (-not $isFirstLoop -and $curUp -ge $lastTotalUpBytes) {
                                $speedUpStr = & $fmtSpeed ($curUp - $lastTotalUpBytes)
                                $speedDownStr = & $fmtSpeed ($curDown - $lastTotalDownBytes)
                            }
                            $lastTotalUpBytes = $curUp; $lastTotalDownBytes = $curDown; $isFirstLoop = $false
                            $totalUpStr = & $fmtTotal $curUp; $totalDownStr = & $fmtTotal $curDown
                        }
                    } catch { $speedUpStr = "API Err"; $isFirstLoop = $true }
                }

                # --- 渲染界面 (使用固定宽度与强力擦除) ---
                $pad = " " * 20 
                $cfgNameFile = Join-Path $ScriptDir ".current_config_name"
                $displayCfgName = "config.json"
                if (Test-Path $cfgNameFile) { $displayCfgName = (Get-Content $cfgNameFile -Raw).Trim() }
                Write-Host "  🔎 监控进程 : $($procInfo.Name)$pad" -ForegroundColor White
                Write-Host "  📂 配置文件 : $displayCfgName$pad" -ForegroundColor DarkGray
                Write-Host "  🆔 进程 PID : $($procInfo.ProcessId)$pad" -ForegroundColor Magenta
                Write-Host "  ⏱ 运行时长 : $uptimeStr$pad" -ForegroundColor Yellow
                Write-Host "  💾 内存占用 : $memMB MB$pad" -ForegroundColor Cyan
                Write-Host "  📄 当前日志 : $logSize / 3.00 MB$pad" -ForegroundColor Gray
                Write-Host "  🔗 TCP 连接 : $conns (系统级)$pad" -ForegroundColor Blue
                
                if ($apiPort) {
                    Write-Host ""
                    Write-Host "  [ 🚀 实时流量 (API: $apiPort) ]$pad" -ForegroundColor Green
                    # 固定网速列宽度为 12 个字符，防止字符抖动和残留
                    Write-Host ("  ⬆ 上传速度 : {0,-12} (总计: {1})$pad" -f $speedUpStr, $totalUpStr) -ForegroundColor Gray
                    Write-Host ("  ⬇ 下载速度 : {0,-12} (总计: {1})$pad" -f $speedDownStr, $totalDownStr) -ForegroundColor White
                } else {
                    Write-Host ""
                    Write-Host "  (未检测到 Clash API，无法显示实时网速)$pad" -ForegroundColor DarkGray
                }

            } else {
                Write-Host "  🆔 进程 PID : (搜索中...)$(' '*30)" -ForegroundColor DarkGray
                Write-Host "  ⚠ 正在启动或发生错误，请按 [L] 查看日志$(' '*30)" -ForegroundColor Red
            }
        } else {
            Write-Host ""
            Write-Host "  ● 服务状态  : 未运行$(' '*30)" -ForegroundColor Red
            Write-Host ""
            Write-Host "    (请按 1 启动服务)$(' '*30)" -ForegroundColor DarkGray
            Write-Host ""
        }
        
        Write-Host ""
        Write-Host "========================================================" -ForegroundColor Cyan
        
        if ([Console]::KeyAvailable) {
            $k = [Console]::ReadKey($true)
            if ($k.Key -eq "Escape") { break }
            if ($k.Key -eq "R") { Reset-Console } 
            if ($k.Key -eq "L") { 
                try { [Console]::CursorVisible = $true } catch {}
                View-Log
                Reset-Console
                try { [Console]::CursorVisible = $false } catch {}
            }
        }
        Start-Sleep -Milliseconds 1000
    }
    try { [Console]::CursorVisible = $true } catch {}
}

function Test-SocketConnect {
    param($HostName, $Port)
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $connectTask = $client.ConnectAsync($HostName, $Port)
        $result = $connectTask.Wait(1000)
        if ($client.Connected) { $client.Close(); return $true }
        return $false
    } catch { return $false }
}

function Test-AdvancedNetwork {
    Reset-Console
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "  🌐  高级网络诊断 (Network Diagnosis)" -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "  提示: 检测过程中按 [Esc] 可强制中止" -ForegroundColor DarkGray
    Write-Host ""

    # --- 中断检测辅助函数 ---
    function Check-Esc {
        if ([Console]::KeyAvailable) {
            $k = [Console]::ReadKey($true)
            if ($k.Key -eq "Escape") {
                Write-Host "`n  🛑 用户强制中止检测。" -ForegroundColor Red
                Start-Sleep -Milliseconds 500
                return $true
            }
        }
        return $false
    }

    # 读取端口配置
    $socksPort = 1080
    if (Test-Path $ConfigPath) {
        try {
            $json = Get-Content $ConfigPath -Raw | ConvertFrom-Json
            foreach ($in in $json.inbounds) {
                if ($in.type -match "socks|mixed") {
                    $socksPort = if ($in.listen_port) { $in.listen_port } else { $in.port }
                    break
                }
            }
        } catch {}
    }

    # 1. 直连 DNS 检查
    Write-Host "  [ 直连检查 - 本机网络 ]" -ForegroundColor Cyan
    $testDomains = @("baidu.com", "microsoft.com")
    foreach ($d in $testDomains) {
        if (Check-Esc) { return } 
        
        Write-Host "  DNS 解析 ($d)... " -NoNewline
        try {
            $ip = [System.Net.Dns]::GetHostAddresses($d) | Select-Object -First 1
            if ($ip) { Write-Host "✅ OK ($($ip.IPAddressToString))" -ForegroundColor Green }
            else { Write-Host "❌ Failed" -ForegroundColor Red }
        } catch { Write-Host "❌ Failed" -ForegroundColor Red }
    }

    # 2. 本地端口检查
    if (Check-Esc) { return } 
    Write-Host "`n  [ 代理检查 - 端口: $socksPort ]" -ForegroundColor Cyan
    Write-Host "  端口监听 ($socksPort)... " -NoNewline
    $listener = Get-NetTCPConnection -LocalPort $socksPort -ErrorAction SilentlyContinue
    if ($listener) { Write-Host "✅ 运行中" -ForegroundColor Green }
    else { Write-Host "❌ 未监听" -ForegroundColor Red }

    # 3. HTTP 代理连接测试 (此处已修复)
    if (Check-Esc) { return } 
    
    $targets = @(
        @{Name="Google  "; Url="http://www.google.com/generate_204"},
        @{Name="GitHub  "; Url="https://github.com"}
    )
    
    foreach ($t in $targets) {
        if (Check-Esc) { return } 
        
        Write-Host "  $($t.Name) ... " -NoNewline
        try {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            
            # [核心修复] 使用原生 WebRequest，它自带 Timeout 属性，无需自定义类
            $req = [System.Net.WebRequest]::Create($t.Url)
            $req.Timeout = 3000  # 设置 3000毫秒 (3秒) 超时
            $req.Method = "GET"
            # 设置代理
            $req.Proxy = New-Object System.Net.WebProxy("http://127.0.0.1:$socksPort")
            
            # 发起请求 (如果超时会直接跳到 catch)
            $resp = $req.GetResponse()
            $sw.Stop()
            
            # 关闭流
            if ($resp) { $resp.Close() }
            
            $color = if ($sw.ElapsedMilliseconds -gt 2000) { "Red" } else { "Green" }
            Write-Host "✅ 通畅 ($($sw.ElapsedMilliseconds)ms)" -ForegroundColor $color
            
        } catch { 
            # 捕获超时或其他网络错误
            Write-Host "❌ 失败/超时" -ForegroundColor Red 
        }
    }
    
    # 4. Socket 直连测试
    Write-Host "`n  [ 外部直连测试 (Socket) ]" -ForegroundColor Cyan
    $socketTests = @{ "1.1.1.1"=53; "223.5.5.5"=53 }
    foreach ($k in $socketTests.Keys) {
        if (Check-Esc) { return }
        
        Write-Host "  Connect $k ... " -NoNewline
        if (Test-SocketConnect -HostName $k -Port $socketTests[$k]) {
            Write-Host "✅ OK" -ForegroundColor Green
        } else {
            Write-Host "❌ Failed" -ForegroundColor Red
        }
    }

    Write-Host "`n  按任意键返回 (Esc 退出)..." -ForegroundColor DarkGray
    Wait-Key | Out-Null
}

# ==================== 系统代理控制 (新增模块) ====================

function Get-InboundPort {
    # 尝试从配置文件解析 HTTP/Mixed 端口
    if (Test-Path $ConfigPath) {
        try {
            $json = Get-Content $ConfigPath -Raw | ConvertFrom-Json
            foreach ($in in $json.inbounds) {
                # 优先寻找 mixed 或 http 类型的入站
                if ($in.type -match "mixed|http") {
                    return if ($in.listen_port) { $in.listen_port } else { $in.port }
                }
            }
        } catch {}
    }
    return 7890 # 默认回退端口，根据你的实际情况修改
}

function Toggle-SystemProxy {
    Reset-Console
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "  🔌 系统代理切换 (System Proxy Toggle)" -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Cyan

    $RegistryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    $current = Get-ItemProperty -Path $RegistryPath -Name ProxyEnable -ErrorAction SilentlyContinue
    $newState = if ($current.ProxyEnable -eq 1) { 0 } else { 1 }
    
    if ($newState -eq 1) {
        $port = Get-InboundPort
        $proxyAddr = "127.0.0.1:$port"
        
        Write-Line "正在开启系统代理 -> $proxyAddr ..." "Cyan"
        Set-ItemProperty -Path $RegistryPath -Name "ProxyEnable" -Value 1
        Set-ItemProperty -Path $RegistryPath -Name "ProxyServer" -Value $proxyAddr
        # 排除列表：本地回环和局域网不走代理
        Set-ItemProperty -Path $RegistryPath -Name "ProxyOverride" -Value "<local>;localhost;127.*;192.168.*;10.*;172.16.*"
        Write-Line "✅ 系统代理已开启" "Green"
    } else {
        Write-Line "正在关闭系统代理..." "Cyan"
        Set-ItemProperty -Path $RegistryPath -Name "ProxyEnable" -Value 0
        Write-Line "✅ 系统代理已关闭" "Yellow"
    }

    # [关键步骤] 调用 WinInet API 立即刷新系统设置 (无需重启浏览器)
    try {
        $signature = @'
        [DllImport("wininet.dll", SetLastError = true)]
        public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int dwBufferLength);
'@
        if (-not ([System.Management.Automation.PSTypeName]'WinInetUtils').Type) {
            Add-Type -MemberDefinition $signature -Name "WinInetUtils" -Namespace "WinInet"
        }
        [WinInet.WinInetUtils]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) # INTERNET_OPTION_SETTINGS_CHANGED
        [WinInet.WinInetUtils]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) # INTERNET_OPTION_REFRESH
        Write-Line "🔄 系统网络状态已刷新" "DarkGray"
    } catch {
        Write-Line "⚠ 刷新 API 调用失败，可能需要重启浏览器生效" "Red"
    }
    
    Start-Sleep -Seconds 1
}

function Check-Config-Silent {
    try {
        $process = Start-Process -FilePath $SingBoxPath -ArgumentList "check -c `"$ConfigPath`"" -NoNewWindow -Wait -PassThru -ErrorAction Stop
        return ($process.ExitCode -eq 0)
    } catch { return $false }
}

function Check-Config {
    Reset-Console
    Write-Host "  正在执行 Sing-box 配置校验..." -NoNewline
    if (Check-Config-Silent) { Write-Host " [通过]" -ForegroundColor Green } 
    else { Write-Host " [失败]" -ForegroundColor Red; Write-Line "请检查配置文件格式。" "Yellow" }
    Wait-Key | Out-Null
}

# ==================== 菜单逻辑 ====================

function Show-Menu {
    Draw-Title
    $state = Get-ServiceState
    
    # 获取当前代理状态用于显示
    $proxyStatus = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyEnable -ErrorAction SilentlyContinue).ProxyEnable
    $proxyStr = if ($proxyStatus -eq 1) { "[开启]" } else { "[关闭]" }
    $proxyColor = if ($proxyStatus -eq 1) { "Green" } else { "DarkGray" }

    Write-Host "  服务状态: " -NoNewline
    if ($state -eq "Running") { Write-Host "运行中" -ForegroundColor Green -NoNewline }
    else { Write-Host "已停止" -ForegroundColor Red -NoNewline }
    
    # 在同一行显示代理状态，节省空间
    Write-Host "    系统代理: " -NoNewline
    Write-Host $proxyStr -ForegroundColor $proxyColor
    
    Write-Host "========================================================" -ForegroundColor DarkGray
    Write-Host "`n  [ 核心控制 ]" -ForegroundColor Cyan
    Write-Line "1. 启动服务 (Start)" "Green"
    Write-Line "2. 停止服务 (Stop)" "Red"
    Write-Line "3. 重启服务 (Restart+)" "Yellow"
    Write-Line "4. 实时监控 (Monitor)" "Cyan"
    
    Write-Host "`n  [ 配置与日志 ]" -ForegroundColor Cyan
    Write-Line "5. 切换配置 (Switch Config)" "Magenta"
    Write-Line "6. 完整日志 (Full Log)" "White"
    Write-Line "7. 网络诊断 (Network Diag)" "Blue"
    Write-Line "8. 检查配置 (Check Config)" "Green"
    
    # ========== 新增选项 ==========
    Write-Host "`n  [ 系统与维护 ]" -ForegroundColor Cyan
    Write-Line "a. 系统代理开关 $proxyStr" "White"  # <--- 这里新增
    Write-Line "b. 更新 WinSW 内核" "DarkYellow"
    Write-Line "c. 开机自启设置 (AutoStart)" "DarkCyan"
    
    Write-Host "========================================================" -ForegroundColor DarkGray
    Write-Host "  0. 停止服务并退出  Q. 退出脚本  Esc. 退出脚本" -ForegroundColor Gray
    Write-Host "========================================================" -ForegroundColor DarkGray
}

function Draw-Title {
    Reset-Console
    Write-Host $TitleArt -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor DarkGray
}

# ==================== 入口 ====================

Check-Admin
Ensure-WinSW

if ($Start) { Start-Service-Wrapper; exit }
if ($Stop) { Stop-Service-Wrapper; exit }
if ($Restart) { Restart-Service-Wrapper; exit }
if ($Monitor) { Show-Monitor; exit }

# ... (前面的代码)

while ($true) {
    Show-Menu
    Write-Host "`n  请选择 (支持按键直接触发)" -ForegroundColor DarkGray
    
    # [修改] 在 ValidKeys 列表中增加 "9"
    $choice = Read-Choice -ValidKeys "1","2","3","4","5","6","7","8","9","a","b","0","q"
    
    switch ($choice) {
        "1" { Start-Service-Wrapper; Wait-Key | Out-Null }
        "2" { Stop-Service-Wrapper; Wait-Key | Out-Null }
        "3" { Show-Restart-Menu }
        "4" { Show-Monitor }
        "5" { Select-Config }
        "6" { View-Log }
        "7" { Test-AdvancedNetwork }
        "8" { Check-Config }
        
        "a" { Toggle-SystemProxy }
        "b" { Update-WinSW }
        "c" { Set-AutoStart }
        "0" { 
            # 建议：退出时是否要自动关闭代理？
            # 如果希望退出脚本时自动关代理，可以取消下面这行的注释
            Toggle-SystemProxy -Off 
            Stop-Service-Wrapper
            if (Test-Path $ConfigNameFile) { Remove-Item $ConfigNameFile -Force }
            Write-Line "正在退出..." "Gray"
            exit 
        }
        "q" { 
            if (Test-Path $ConfigNameFile) { Remove-Item $ConfigNameFile -Force }
            exit 
        }
        "Escape" { 
            if (Test-Path $ConfigNameFile) { Remove-Item $ConfigNameFile -Force }
            exit 
        }
    }
}

