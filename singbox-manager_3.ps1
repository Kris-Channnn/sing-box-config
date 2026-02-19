<#
.SYNOPSIS
    Sing-box Manager (WinSW Edition) v8.6 Final [Cyberpunk UI]
#>

param(
    [switch]$Start,
    [switch]$Stop,
    [switch]$Restart,
    [switch]$Monitor,
    [int]$MonitorRefreshMs = 1000
)

# ==================== 0. 环境初始化 ====================
try {
    $psWindow = (Get-Host).UI.RawUI
    $newSize = $psWindow.WindowSize
    $newSize.Width = 130; $newSize.Height = 40
    $psWindow.WindowSize = $newSize
    $bufferSize = $psWindow.BufferSize
    $bufferSize.Width = 130; $bufferSize.Height = 2000
    $psWindow.BufferSize = $bufferSize
}
catch {}

$ErrorActionPreference = "SilentlyContinue"
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
Set-Location $ScriptDir

# ==================== 1. 核心定义 ====================
$ExeName = "sing-box"
$ServiceBase = "singbox-service" 
$ServiceName = "Sing-box-Service"
$ServiceTitle = "Sing-box Core Service"

$SingBoxPath = Join-Path $ScriptDir "$ExeName.exe"
$ConfigPath = Join-Path $ScriptDir "config.json"
$ServiceExe = Join-Path $ScriptDir "$ServiceBase.exe"
$ServiceXml = Join-Path $ScriptDir "$ServiceBase.xml"
$LogFile = Join-Path $ScriptDir "$ServiceBase.err.log" 
$PidFile = Join-Path $ScriptDir "service.pid"
$ConfigBackupDir = Join-Path $ScriptDir "config_backups"
$LogArchiveDir = Join-Path $ScriptDir "log_archives"
$ConfigNameFile = Join-Path $ScriptDir ".current_config_name"
$WinSWUrl = "https://github.com/winsw/winsw/releases/download/v2.12.0/WinSW.NET461.exe"
$TaskName = "SingBox_Delayed_Start"

# ==================== 2. 视觉引擎 (Cyberpunk) ====================

function Write-TrueColor {
    param([string]$Text, [int]$R, [int]$G, [int]$B, [switch]$NewLine)
    $Esc = [char]27
    $Seq = "$Esc[38;2;$R;$G;${B}m"
    if ($NewLine) { Write-Host "$Seq$Text$Esc[0m" } else { Write-Host "$Seq$Text$Esc[0m" -NoNewline }
}

function Draw-Separator {
    # 霓虹渐变分割线
    $Line = "════════════════════════════════════════════════════════════════"
    Write-TrueColor $Line 80 0 80 -NewLine
}

function Draw-Gradient-Art {
    $ArtLines = @(
        "███████╗██╗███╗   ██╗ ██████╗        ██████╗  ██████╗ ██╗  ██╗",
        "██╔════╝██║████╗  ██║██╔════╝        ██╔══██╗██╔═══██╗╚██╗██╔╝",
        "███████╗██║██╔██╗ ██║██║  ███╗ _____ ██████╔╝██║   ██║ ╚███╔╝ ",
        "╚════██║██║██║╚██╗██║██║   ██║|_____|██╔══██╗██║   ██║ ██╔██╗ ",
        "███████║██║██║ ╚████║╚██████╔╝       ██████╔╝╚██████╔╝██╔╝ ██╗",
        "╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝        ╚═════╝  ╚═════╝ ╚═╝  ╚═╝"
    )
    $Colors = @(
        @{R = 255; G = 20; B = 147 }, @{R = 255; G = 0; B = 255 }, @{R = 186; G = 85; B = 211 },
        @{R = 138; G = 43; B = 226 }, @{R = 0; G = 191; B = 255 }, @{R = 0; G = 255; B = 255 }
    )
    Write-Host ""
    for ($i = 0; $i -lt $ArtLines.Count; $i++) {
        $c = $Colors[$i]
        Write-TrueColor (" " * 8 + $ArtLines[$i]) $c.R $c.G $c.B -NewLine
    }
    Write-Host ""
    Write-TrueColor "                    >>> SING-BOX MANAGER v8.6 <<<" 255 215 0 -NewLine
    Write-Host ""
}

function Draw-Sub-Header {
    param([string]$Title)
    Reset-Console
    Write-Host ""
    Write-TrueColor " :: $Title :: " 0 255 255 -NewLine
    Write-Host ""
    Draw-Separator
}

# ==================== 3. 基础工具 ====================

function Reset-Console {
    try { [Console]::ResetColor(); Clear-Host } catch { Clear-Host }
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
            if ([Console]::ReadKey($true).Key -eq "Escape") { return "Escape" }
            return "Any"
        }
        Start-Sleep -Milliseconds 50
    }
}

function Read-Choice {
    param([string[]]$ValidKeys)
    while ($true) {
        if ([Console]::KeyAvailable) {
            $k = [Console]::ReadKey($true)
            if ($k.Key -eq "Escape") { return "Escape" }
            foreach ($vk in $ValidKeys) { if ($k.KeyChar.ToString().ToLower() -eq $vk.ToLower()) { return $vk } }
        }
        Start-Sleep -Milliseconds 50
    }
}

function Check-Admin {
    if (-not (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "[!] 需要管理员权限" -ForegroundColor Red; exit
    }
}

# ==================== 4. 核心逻辑 ====================

function Ensure-WinSW {
    if (-not (Test-Path $SingBoxPath)) { Write-Host "❌ 缺 $ExeName.exe" -ForegroundColor Red; exit }
    if (-not (Test-Path $ServiceExe)) {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $WinSWUrl -OutFile $ServiceExe -UseBasicParsing
        }
        catch { Write-Line "下载 WinSW 失败" "Red"; exit }
    }
    if (-not (Test-Path $ServiceXml)) {
        Set-Content $ServiceXml "<service><id>$ServiceName</id><name>$ServiceTitle</name><executable>%BASE%\$ExeName.exe</executable><arguments>run -c config.json</arguments><onfailure action=`"restart`" delay=`"5 sec`"/><log mode=`"roll-by-size`"><sizeThreshold>3072</sizeThreshold><keepFiles>5</keepFiles></log></service>" -Encoding UTF8
    }
}

function Get-ServiceState {
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($null -eq $svc) { return "NotInstalled" }
    return $svc.Status.ToString()
}

function Start-Service-Wrapper {
    Ensure-WinSW; Archive-Old-Logs
    if ((Get-ServiceState) -eq "Running") { Write-Line "已在运行" "Yellow"; return }
    Write-Line "🚀 启动中..." "Cyan"
    Start-Process -FilePath $ServiceExe -ArgumentList "start" -Wait -NoNewWindow
    Start-Sleep -Seconds 1
}

function Stop-Service-Wrapper {
    if ((Get-ServiceState) -eq "Running") {
        Write-Line "🛑 停止中..." "Red"
        Start-Process -FilePath $ServiceExe -ArgumentList "stop" -Wait -NoNewWindow
    }
    else { Write-Line "未运行" "DarkGray" }
}

function Restart-Service-Wrapper { Stop-Service-Wrapper; Start-Sleep 1; Start-Service-Wrapper }

function Update-WinSW {
    Draw-Sub-Header "更新内核"
    Write-Line "即将停止服务并更新 Service Wrapper" "Yellow"
    Write-Host "`n  确认更新? (Y/N)" -ForegroundColor DarkGray
    if ((Read-Choice "y", "n") -eq "y") {
        Stop-Service-Wrapper
        try {
            Invoke-WebRequest -Uri $WinSWUrl -OutFile $ServiceExe -UseBasicParsing
            Write-Line "✅ 更新成功" "Green"
        }
        catch { Write-Line "❌ 失败: $_" "Red" }
        Wait-Key | Out-Null
    }
}

function Set-AutoStart {
    Draw-Sub-Header "开机自启配置"
    Write-Line "1. 标准自启 (Windows Service)" "Cyan"
    Write-Line "2. 延迟启动 (Scheduled Task 30s)" "Magenta"
    Write-Line "3. 禁用自启" "Gray"
    
    Write-Host "`n  请选择 (1-3): " -NoNewline -ForegroundColor DarkGray
    $c = Read-Choice "1", "2", "3"
    if ($c -eq "Escape") { return }
    Write-Host ""
    
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue }
    
    switch ($c) {
        "1" { Set-Service -Name $ServiceName -StartupType Automatic; Write-Line "✅ 已设为标准自启" "Green" }
        "2" {
            Set-Service -Name $ServiceName -StartupType Manual
            $act = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -Command `"Start-Sleep -s 30; Start-Service '$ServiceName'`""
            Register-ScheduledTask -TaskName $TaskName -Action $act -Trigger (New-ScheduledTaskTrigger -AtLogOn) -Principal (New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest) -Force | Out-Null
            Write-Line "✅ 已设为延迟启动" "Green"
        }
        "3" { Set-Service -Name $ServiceName -StartupType Manual; Write-Line "✅ 已禁用自启" "Yellow" }
    }
    Wait-Key | Out-Null
}

function Show-Restart-Menu {
    Draw-Sub-Header "重启选项"
    Write-Line "1. 强制重启 (Direct)" "Red"
    Write-Line "2. 安全重载 (Safe Reload)" "Green"
    
    $c = Read-Choice "1", "2"
    if ($c -eq "1") { Restart-Service-Wrapper }
    elseif ($c -eq "2") {
        if (Check-Config-Silent) { Backup-Config-Wrapper; Restart-Service-Wrapper }
        else { Write-Line "❌ 配置校验失败，取消重启" "Red"; Wait-Key | Out-Null }
    }
}

# ==================== 5. 日志/配置/网络 ====================

function Backup-Config-Wrapper {
    if (Test-Path $ConfigPath) {
        if (-not (Test-Path $ConfigBackupDir)) { New-Item -Type Directory -Path $ConfigBackupDir | Out-Null }
        Copy-Item $ConfigPath "$ConfigBackupDir\config_$(Get-Date -f 'yyyyMMdd_HHmmss').json" -Force
    }
}

function Archive-Old-Logs {
    if (-not (Test-Path $LogArchiveDir)) { New-Item -Type Directory -Path $LogArchiveDir | Out-Null }
    $logs = Get-ChildItem $ScriptDir -Filter "$ServiceBase.*.err.log" | ? { $_.Name -match "$ServiceBase\.\d+\.err\.log$" }
    foreach ($l in $logs) {
        try {
            $f = "$LogArchiveDir\$(Get-Date -f 'yyyy-MM')"
            if (-not (Test-Path $f)) { New-Item -Type Directory -Path $f | Out-Null }
            Compress-Archive -Path $l.FullName -DestinationPath "$f\$($l.Name)_$(Get-Date -f 'HHmmss').zip" -Force -ErrorAction Stop
            Remove-Item $l.FullName -Force
        }
        catch {}
    }
}

function Search-Log-Internal {
    param([string]$Keyword)
    Draw-Sub-Header "日志搜索: $Keyword"
    if (-not (Test-Path $LogFile)) { return }
    
    try {
        $matches = Select-String -Path $LogFile -Pattern $Keyword -Context 1,1 | Select-Object -Last 100
        if ($matches) {
            $lineMap = @{}
            foreach ($m in $matches) {
                $cur = $m.LineNumber
                if ($m.Context.PreContext) { if (-not $lineMap[$cur-1]) { $lineMap[$cur-1] = @{T=$m.Context.PreContext[0];M=$false} } }
                $lineMap[$cur] = @{T=$m.Line;M=$true}
                if ($m.Context.PostContext) { if (-not $lineMap[$cur+1]) { $lineMap[$cur+1] = @{T=$m.Context.PostContext[0];M=$false} } }
            }
            $last = -1
            foreach ($n in ($lineMap.Keys | Sort)) {
                $txt = $lineMap[$n].T.Trim() -replace "\+0800\s*", ""
                
                # [修改点] 去掉 ,5 实现紧凑显示
                $pfx = "[{0}]" -f $n
                
                if ($last -ne -1 -and $n -ne ($last+1)) { Write-Host "  -------" -ForegroundColor DarkGray }
                if ($lineMap[$n].M) {
                    Write-Host "$pfx " -NoNewline -ForegroundColor Cyan
                    if ($txt -match 'error|fatal|panic') { Write-Host ">> $txt" -ForegroundColor Red }
                    elseif ($txt -match 'warn') { Write-Host ">> $txt" -ForegroundColor Yellow }
                    else { Write-Host ">> $txt" -ForegroundColor White }
                } else { Write-Host "$pfx    $txt" -ForegroundColor DarkGray }
                $last = $n
            }
        } else { Write-Line "未找到结果" "Yellow" }
    } catch { Write-Line "搜索错误: $_" "Red" }
    Wait-Key | Out-Null
}

function View-Log {
    $filterWarn = $false
    function Header {
        Reset-Console
        # 顶部标题
        Write-Host " 实时日志流 (Live Log) " -NoNewline -BackgroundColor Yellow -ForegroundColor Black
        Write-Host " $LogFile " -BackgroundColor Black -ForegroundColor DarkGray
        
        $st = if($filterWarn){"开启"}else{"关闭"}
        
        # 菜单栏
        Write-Host " [F]过滤警告:$st  [C]清空  [R]重载  [S]搜索  [Esc]退出 " -ForegroundColor White -BackgroundColor DarkBlue
        Draw-Separator
    }
    Header
    if (-not (Test-Path $LogFile)) { Wait-Key | Out-Null; return }

    $curLn = 0; try { $curLn = (Get-Content $LogFile | Measure -Line).Lines } catch {}
    $reader = $null; $stream = $null; $lastSz = (Get-Item $LogFile).Length

    try {
        $stream = [System.IO.File]::Open($LogFile, 'Open', 'Read', 'ReadWrite')
        $reader = New-Object System.IO.StreamReader($stream)
        $reader.BaseStream.Seek(0, [System.IO.SeekOrigin]::End) | Out-Null
        
        while ($true) {
            $line = $reader.ReadLine()
            if ($line) {
                $line = $line -replace "\+0800\s*", ""; $curLn++
                
                # [修改点] 去掉 ,5 实现紧凑显示： [1234] 而不是 [ 1234]
                $pfx = "[{0}]" -f $curLn
                
                $imp = ($line -match "WARN|ERROR|FATAL|PANIC")
                if (-not ($filterWarn -and -not $imp)) {
                    Write-Host "$pfx " -NoNewline -ForegroundColor Cyan
                    if ($line -match "ERROR|FATAL|panic") { Write-Host $line -ForegroundColor Red }
                    elseif ($line -match "WARN") { Write-Host $line -ForegroundColor Yellow }
                    elseif ($line -match "INFO") { Write-Host $line -ForegroundColor White }
                    else { Write-Host $line -ForegroundColor DarkGray }
                }
            } else {
                Start-Sleep -m 100
                try {
                    $nowSz = (Get-Item $LogFile).Length
                    if ($nowSz -lt $lastSz) { 
                        Write-Line ">>> 日志轮转重置 <<<" "Magenta"
                        $reader.Close(); $stream.Close(); Start-Sleep -m 200
                        $stream = [System.IO.File]::Open($LogFile, 'Open', 'Read', 'ReadWrite')
                        $reader = New-Object System.IO.StreamReader($stream)
                        $curLn = 0; $lastSz = $nowSz
                    } else { $lastSz = $nowSz }
                } catch {}
            }
            if ([Console]::KeyAvailable) {
                $k = [Console]::ReadKey($true).Key
                if ($k -eq "Escape") { break }
                if ($k -eq "F") { $filterWarn = -not $filterWarn; Header }
                if ($k -eq "S") {
                    $reader.Close(); $stream.Close()
                    $kw = Read-Host "`n  搜索关键词"; if($kw){Search-Log-Internal $kw}
                    Header; $stream=[System.IO.File]::Open($LogFile,'Open','Read','ReadWrite');$reader=New-Object System.IO.StreamReader($stream);$reader.BaseStream.Seek(0,[System.IO.SeekOrigin]::End)|Out-Null;$curLn=(Get-Content $LogFile|Measure -Line).Lines
                }
                if ($k -eq "C") { 
                    $reader.Close(); $stream.Close()
                    try{Clear-Content $LogFile -ErrorAction Stop;$curLn=0}catch{}; Header
                    $stream=[System.IO.File]::Open($LogFile,'Open','Read','ReadWrite');$reader=New-Object System.IO.StreamReader($stream);$reader.BaseStream.Seek(0,[System.IO.SeekOrigin]::End)|Out-Null;$lastSz=(Get-Item $LogFile).Length
                }
                if ($k -eq "R") {
                    $reader.Close(); $stream.Close(); Header
                    $curLn=(Get-Content $LogFile|Measure -Line).Lines
                    $stream=[System.IO.File]::Open($LogFile,'Open','Read','ReadWrite');$reader=New-Object System.IO.StreamReader($stream);$reader.BaseStream.Seek(0,[System.IO.SeekOrigin]::End)|Out-Null;$lastSz=(Get-Item $LogFile).Length
                }
            }
        }
    } finally { if($reader){$reader.Close()}; if($stream){$stream.Close()} }
}

function Select-Config {
    Draw-Sub-Header "切换配置"
    $cfgs = Get-ChildItem $ScriptDir -Filter "*.json" | ? { $_.Name -notin "service.json","stats.json" -and $_.Name -notmatch "singbox-service|config_20" }
    if ($cfgs.Count -eq 0) { Write-Line "无其他配置文件" "Red"; Wait-Key|Out-Null; return }

    Write-Line "当前: config.json" "DarkGray"; Write-Host ""
    for ($i=0; $i -lt $cfgs.Count; $i++) {
        $n = $cfgs[$i].Name
        Write-Host "  " -NoNewline
        Write-Host " [$($i+1)] " -ForegroundColor Black -BackgroundColor Cyan -NoNewline
        Write-Host " $n " -ForegroundColor Cyan
    }
    
    # [修复] 增加返回提示，使用黄色高亮
    Write-Host "`n  选择序号 (0 或 Esc 返回): " -NoNewline -ForegroundColor Yellow
    
    $in = Read-Host; 
    # 支持输入 0 或 Esc 逻辑
    if (-not $in -match '^\d+$' -or $in -eq "0") { return }
    
    $sel = $cfgs[[int]$in - 1]
    if ($sel.Name -ne "config.json") {
        Backup-Config-Wrapper
        Copy-Item $sel.FullName $ConfigPath -Force
        Set-Content $ConfigNameFile $sel.Name -Force
        Write-Line "✅ 已切换为 $($sel.Name)" "Green"
        Write-Host "  立即重启? (Y/N)" -ForegroundColor DarkGray
        if ((Read-Choice "y","n") -eq "y") { Restart-Service-Wrapper }
    }
}

function Show-Monitor {
    Reset-Console; try{[Console]::CursorVisible=$false}catch{}
    $lastRot=Get-Date; $msg=""; $port=$null; $sec=""; $lUp=0; $lDown=0; $first=$true
    
    if(Test-Path $ConfigPath){try{$j=Get-Content $ConfigPath -Raw|ConvertFrom-Json;$port=($j.experimental.clash_api.external_controller -split ":")[-1];$sec=$j.experimental.clash_api.secret}catch{}}

    while($true) {
        [Console]::SetCursorPosition(0,0)
        # [修复] 标题汉化，菜单栏增亮
        Write-Host " 实时监控面板 (Monitor) " -NoNewline -BackgroundColor DarkCyan -ForegroundColor Black
        Write-Host " [Esc]返回  [L]日志  [R]刷新 " -BackgroundColor Black -ForegroundColor White
        Draw-Separator

        if(((Get-Date)-$lastRot).TotalSeconds -gt 2){
            $r = Get-ChildItem $ScriptDir -Filter "$ServiceBase.*.err.log" | ? {$_.Name -match "$ServiceBase\.\d+\.err\.log$"}
            if($r){$msg="⚠ 日志已轮转, 发现 $($r.Count) 个旧文件"}else{$msg=""}
            $lastRot=Get-Date
        }
        if($msg){Write-Host "  $msg$(' '*20)" -ForegroundColor Yellow}else{Write-Host "  $(' '*50)"}
        Write-Host "--------------------------------------------------------" -ForegroundColor DarkGray

        $svc=Get-Service $ServiceName -ErrorAction SilentlyContinue
        if($svc -and $svc.Status -eq "Running"){
            $proc = if(Test-Path $PidFile){Get-CimInstance Win32_Process -Filter "ProcessId=$([int](Get-Content $PidFile))" -ErrorAction SilentlyContinue}else{$null}
            if(!$proc){$proc=Get-CimInstance Win32_Process -Filter "Name='$ExeName.exe'"|select -First 1}
            
            Write-Host "  ● 服务状态 : " -NoNewline -ForegroundColor Gray; Write-Host "Running" -ForegroundColor Green
            if($proc){
                $mem=[math]::Round($proc.WorkingSetSize/1MB,2); $uptime="N/A"
                try{$t=$proc.CreationDate;if($t -is [string]){$t=[Management.ManagementDateTimeConverter]::ToDateTime($t)};$u=(Get-Date)-$t;$uptime="{0:D2}:{1:D2}:{2:D2}" -f $u.Hours,$u.Minutes,$u.Seconds}catch{}
                $conns=(Get-NetTCPConnection -OwningProcess $proc.ProcessId -State Established -ErrorAction SilentlyContinue).Count
                
                $spU="0 KB/s";$spD="0 KB/s";$totU="0 MB";$totD="0 MB"
                if($port){
                    try{
                        $s=Invoke-RestMethod -Uri "http://127.0.0.1:$port/connections" -Headers @{Authorization="Bearer $sec"} -TimeoutSec 1
                        $cu=$s.uploadTotal; $cd=$s.downloadTotal
                        if(!$first -and $cu -ge $lUp){
                            $spU = if(($cu-$lUp)-gt 1MB){"{0:N2} MB/s" -f (($cu-$lUp)/1MB)}else{"{0:N0} KB/s" -f (($cu-$lUp)/1KB)}
                            $spD = if(($cd-$lDown)-gt 1MB){"{0:N2} MB/s" -f (($cd-$lDown)/1MB)}else{"{0:N0} KB/s" -f (($cd-$lDown)/1KB)}
                        }
                        $lUp=$cu; $lDown=$cd; $first=$false
                        $totU="{0:N2} MB" -f ($cu/1MB); $totD="{0:N2} MB" -f ($cd/1MB)
                    }catch{$spU="Err"}
                }
                
                $pad=" "*20
                Write-Host "  🔎 进程PID : $($proc.ProcessId)$pad" -ForegroundColor Magenta
                Write-Host "  ⏱ 运行时长 : $uptime$pad" -ForegroundColor Yellow
                Write-Host "  💾 内存占用 : $mem MB$pad" -ForegroundColor Cyan
                Write-Host "  🔗 TCP连接 : $conns$pad" -ForegroundColor Blue
                Write-Host ""
                Write-Host "  [ 🚀 流量统计 (API:$port) ]$pad" -ForegroundColor Green
                Write-Host ("  ⬆ 上传 : {0,-10} (总: {1})$pad" -f $spU,$totU) -ForegroundColor Gray
                Write-Host ("  ⬇ 下载 : {0,-10} (总: {1})$pad" -f $spD,$totD) -ForegroundColor White
            }
        } else {
            Write-Host "  ● 服务状态 : " -NoNewline -ForegroundColor Gray; Write-Host "Stopped$(' '*20)" -ForegroundColor Red
        }
        
        Write-Host "`n"
        Draw-Separator
        if([Console]::KeyAvailable){
            $k=[Console]::ReadKey($true).Key; if($k -eq "Escape"){break}
            if($k -eq "L"){try{[Console]::CursorVisible=$true}catch{};View-Log;Reset-Console;try{[Console]::CursorVisible=$false}catch{}}
            if($k -eq "R"){Reset-Console}
        }
        Start-Sleep -m 1000
    }
    try{[Console]::CursorVisible=$true}catch{}
}

function Test-AdvancedNetwork {
    Draw-Sub-Header "网络诊断"
    # [修复] 增加提示文案
    Write-Host "  提示: 检测过程中按 [Esc] 可强制中止" -ForegroundColor DarkGray
    Write-Host ""
    
    function ChkEsc { if([Console]::KeyAvailable -and [Console]::ReadKey($true).Key -eq "Escape"){Write-Line "中止" "Red"; return $true};return $false }
    
    $sp=1080; if(Test-Path $ConfigPath){try{$j=Get-Content $ConfigPath -Raw|ConvertFrom-Json;$sp=if($j.inbounds[0].listen_port){$j.inbounds[0].listen_port}else{$j.inbounds[0].port}}catch{}}

    Write-Line "[ 直连 DNS ]" "Cyan"
    foreach($d in "baidu.com","microsoft.com"){
        if(ChkEsc){return}; Write-Host "  $d : " -NoNewline
        try{ $i=[System.Net.Dns]::GetHostAddresses($d)|select -First 1; if($i){Write-Host "OK" -F Green}else{Write-Host "Fail" -F Red} }catch{Write-Host "Err" -F Red}
    }

    Write-Line "`n[ 本地代理 : $sp ]" "Cyan"
    if(Get-NetTCPConnection -LocalPort $sp -ErrorAction SilentlyContinue){Write-Line "端口监听: OK" "Green"}else{Write-Line "端口监听: Fail" "Red"}
    
    Write-Line "[ HTTP 延迟 ]" "Cyan"
    foreach($t in @(@{N="Google";U="http://google.com/gen_204"},@{N="GitHub";U="https://github.com"})){
        if(ChkEsc){return}; Write-Host "  $($t.N) : " -NoNewline
        try{
            $req=[System.Net.WebRequest]::Create($t.U); $req.Timeout=3000; $req.Method="HEAD"
            $req.Proxy=New-Object System.Net.WebProxy("127.0.0.1:$sp")
            $sw=[System.Diagnostics.Stopwatch]::StartNew(); $null=$req.GetResponse(); $sw.Stop()
            Write-Host "$($sw.ElapsedMilliseconds)ms" -F Green
        }catch{Write-Host "Timeout/Err" -F Red}
    }
    Wait-Key | Out-Null
}

function Toggle-SystemProxy {
    param([string]$Mode = "Toggle")
    $Reg = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    $cur = (Get-ItemProperty $Reg ProxyEnable -EA 0).ProxyEnable
    $set = -1
    
    if ($Mode -eq "Toggle") { $set = if ($cur -eq 1) { 0 }else { 1 } }
    elseif ($Mode -eq "On" -and $cur -ne 1) { $set = 1 }
    elseif ($Mode -eq "Off" -and $cur -ne 0) { $set = 0 }
    
    if ($set -eq 1) {
        Draw-Sub-Header "系统代理: 开启"
        $p = 7890; try { $j = Get-Content $ConfigPath -Raw | ConvertFrom-Json; $p = $j.inbounds | ? { $_.type -match "mixed|http" } | select -exp listen_port -First 1 }catch {}
        Set-ItemProperty $Reg ProxyEnable 1; Set-ItemProperty $Reg ProxyServer "127.0.0.1:$p"
        Write-Line "已开启 (127.0.0.1:$p)" "Green"
    }
    elseif ($set -eq 0) {
        if ($Mode -eq "Toggle") { Draw-Sub-Header "系统代理: 关闭"; Write-Line "已关闭" "Yellow" }
        Set-ItemProperty $Reg ProxyEnable 0
    }
    
    try {
        $sig = '[DllImport("wininet.dll",SetLastError=true)]public static extern bool InternetSetOption(IntPtr h,int o,IntPtr b,int l);'
        $t = Add-Type -MemberDefinition $sig -Name "WinInet" -Namespace "Win" -PassThru
        $t::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0)
        $t::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0)
    }
    catch {}

    if ($Mode -eq "Toggle") { Start-Sleep 1 }
}

function Check-Config-Silent { try { return (Start-Process $SingBoxPath "check -c `"$ConfigPath`"" -NoNewWindow -Wait -PassThru).ExitCode -eq 0 }catch { return $false } }
function Check-Config { Draw-Sub-Header "配置校验"; if (Check-Config-Silent) { Write-Line "✔ 校验通过" "Green" }else { Write-Line "❌ 校验失败" "Red" }; Wait-Key | Out-Null }

# ==================== 6. 主菜单 ====================

function Show-Menu {
    Reset-Console; Draw-Gradient-Art; Write-TrueColor "  ════════════════════════════════════════════════════════════════" 80 0 80 -NewLine
    
    $st = Get-ServiceState; $pr = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" ProxyEnable -EA 0).ProxyEnable
    Write-Host "  "; if ($st -eq "Running") { Write-Host " ● CORE: ONLINE " -NoNewline -B Green -F Black }else { Write-Host " ● CORE: OFFLINE " -NoNewline -B Red -F White }
    Write-Host "  "; if ($pr -eq 1) { Write-Host " ⇄ PROXY: ON " -NoNewline -B Cyan -F Black }else { Write-Host " ⇄ PROXY: OFF " -NoNewline -B DarkGray -F White }
    Write-Host "                                   " -NoNewline; Write-TrueColor ":: SYSTEM READY" 100 100 100 -NewLine; Write-Host ""

    function Btn($i, $t, $c, $nl = $false) {
        Write-Host " $i " -NoNewline -B $c -F Black; Write-Host " $t".PadRight(16) -NoNewline -F $c
        if ($nl) { Write-Host "" }else { Write-Host "    " -NoNewline }
    }

    Write-Host "  [ 核心控制 ]" -F DarkGray
    Btn "1" "启动服务" "Green"; Btn "2" "停止服务" "Red" $true
    Btn "3" "重启服务" "Yellow"; Btn "4" "实时监控" "Cyan" $true
    Write-Host ""

    Write-Host "  [ 功能管理 ]" -F DarkGray
    Btn "5" "切换配置" "Magenta"; Btn "6" "查看日志" "White" $true
    Btn "7" "网络诊断" "Blue"; Btn "8" "配置校验" "Gray" $true
    Write-Host ""

    Write-Host "  [ 系统维护 ]" -F DarkGray
    Btn "A" "系统代理开关" "DarkYellow"; Btn "B" "更新内核" "DarkYellow" $true
    Btn "C" "开机自启设置" "DarkYellow" $true
    
    Write-Host "`n  ════════════════════════════════════════════════════════════════" -F DarkGray
    Write-Host "   0. 停止并退出    Q. 仅退出" -F Gray
}

# ==================== 7. 入口 ====================

Check-Admin; Ensure-WinSW
if ($Start) { Start-Service-Wrapper; exit }; if ($Stop) { Stop-Service-Wrapper; exit }; if ($Restart) { Restart-Service-Wrapper; exit }; if ($Monitor) { Show-Monitor; exit }

while ($true) {
    Show-Menu; Write-Host "`n  指令 > " -NoNewline -F DarkGray
    $c = Read-Choice "1", "2", "3", "4", "5", "6", "7", "8", "a", "b", "c", "0", "q"
    switch ($c) {
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
        "0" { Toggle-SystemProxy "Off"; Stop-Service-Wrapper; if (Test-Path $ConfigNameFile) { Del $ConfigNameFile -Force }; exit }
        "q" { if (Test-Path $ConfigNameFile) { Del $ConfigNameFile -Force }; exit }
        "Escape" { if (Test-Path $ConfigNameFile) { Del $ConfigNameFile -Force }; exit }
    }
}