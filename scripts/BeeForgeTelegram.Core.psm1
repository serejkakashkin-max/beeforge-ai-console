Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:TelegramRoot = Split-Path $PSScriptRoot -Parent
$script:TelegramToolRoot = Join-Path $script:TelegramRoot 'tools\telegram-bridge\v1.0.0'
$script:TelegramConfigPath = Join-Path $script:TelegramRoot 'config\telegram.json'
$script:TelegramLegacyStateRoot = Join-Path $env:LOCALAPPDATA 'BeeForge\Telegram'
$script:TelegramStateRoot = Join-Path $script:TelegramRoot 'runtime\telegram'
$script:TelegramSecretRoot = Join-Path $script:TelegramRoot 'secrets'
$script:TelegramTokenPath = Join-Path $script:TelegramSecretRoot 'telegram-token.dpapi'
$script:TelegramKeyPath = Join-Path $script:TelegramSecretRoot 'telegram-bridge.key'
$script:TelegramLegacyTokenPath = Join-Path $script:TelegramLegacyStateRoot 'telegram-token.dpapi'
$script:TelegramLegacyKeyPath = Join-Path $script:TelegramLegacyStateRoot 'bridge.key'
$script:TelegramPidPath = Join-Path $script:TelegramStateRoot 'bridge.pid'
$script:TelegramStatusPath = Join-Path $script:TelegramStateRoot 'status.json'
$script:TelegramStopMarkerPath = Join-Path $script:TelegramStateRoot 'manual-stop'
$script:TelegramLogPath = Join-Path $script:TelegramStateRoot 'telegram-bridge.log'
$script:TelegramStdoutPath = Join-Path $script:TelegramStateRoot 'bridge.stdout.log'
$script:TelegramStderrPath = Join-Path $script:TelegramStateRoot 'bridge.stderr.log'
$script:TelegramTaskName = 'BeeForge Telegram Bridge'
$script:TelegramRunnerPath = Join-Path $script:TelegramRoot 'scripts\Run-BeeTelegramBridge.ps1'

function Write-BeeTelegramUtf8([string]$Path,[string]$Text) {
    $parent=Split-Path $Path -Parent
    if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    [IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false))
}

function Protect-BeeTelegramFile([string]$Path) {
    try {
        $identity=[Security.Principal.WindowsIdentity]::GetCurrent().Name
        $acl=Get-Acl -LiteralPath $Path
        $acl.SetAccessRuleProtection($true,$false)
        $acl.SetOwner((New-Object Security.Principal.NTAccount($identity)))
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($identity,'FullControl','Allow')))
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule('SYSTEM','FullControl','Allow')))
        Set-Acl -LiteralPath $Path -AclObject $acl
    } catch {
        throw "Не удалось ограничить доступ к секретному файлу '$Path': $($_.Exception.Message)"
    }
}

function Initialize-BeeTelegram {
    foreach($dir in @((Split-Path $script:TelegramConfigPath -Parent),$script:TelegramStateRoot,$script:TelegramSecretRoot,(Split-Path $script:TelegramLogPath -Parent))){
        if(-not(Test-Path -LiteralPath $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
    }
    if(-not(Test-Path -LiteralPath $script:TelegramTokenPath)-and(Test-Path -LiteralPath $script:TelegramLegacyTokenPath)){
        Copy-Item -LiteralPath $script:TelegramLegacyTokenPath -Destination $script:TelegramTokenPath -Force
        Protect-BeeTelegramFile $script:TelegramTokenPath
    }
    if(-not(Test-Path -LiteralPath $script:TelegramKeyPath)-and(Test-Path -LiteralPath $script:TelegramLegacyKeyPath)){
        Copy-Item -LiteralPath $script:TelegramLegacyKeyPath -Destination $script:TelegramKeyPath -Force
        Protect-BeeTelegramFile $script:TelegramKeyPath
    }
    if(-not(Test-Path -LiteralPath $script:TelegramConfigPath)){
        $defaults=[ordered]@{
            enabled=$false
            allowedUserId=''
            allowedChatId=''
            bridgePort=47655
            summaryIntervalMinutes=0
            notifyDelegation=$true
            notifyCompletion=$true
            notifyErrors=$true
            muted=$false
            allowedProjects=@()
            allowPreviouslyOpenedProjects=$true
            defaultProjectRoot='C:\AI\Projects'
            pinnedStatus=$true
            voiceEnabled=$true
            voicePort=47656
            voiceModel='small'
            voiceLanguage='auto'
        }
        Write-BeeTelegramUtf8 $script:TelegramConfigPath ($defaults|ConvertTo-Json -Depth 8)
    }
    if(-not(Test-Path -LiteralPath $script:TelegramKeyPath)){
        $bytes=New-Object byte[] 32
        [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
        Write-BeeTelegramUtf8 $script:TelegramKeyPath ([Convert]::ToBase64String($bytes))
        Protect-BeeTelegramFile $script:TelegramKeyPath
    }
}

function Get-BeeTelegramPaths {
    Initialize-BeeTelegram
    [pscustomobject]@{Root=$script:TelegramRoot;ToolRoot=$script:TelegramToolRoot;Config=$script:TelegramConfigPath;State=$script:TelegramStateRoot;Secrets=$script:TelegramSecretRoot;Token=$script:TelegramTokenPath;Key=$script:TelegramKeyPath;Pid=$script:TelegramPidPath;Status=$script:TelegramStatusPath;StopMarker=$script:TelegramStopMarkerPath;Log=$script:TelegramLogPath;Stdout=$script:TelegramStdoutPath;Stderr=$script:TelegramStderrPath;TaskName=$script:TelegramTaskName;Runner=$script:TelegramRunnerPath}
}

function Install-BeeTelegramScheduledTask {
    if(-not(Test-Path -LiteralPath $script:TelegramRunnerPath)){throw "Не найден запускатель Telegram Bridge: $script:TelegramRunnerPath"}
    Import-Module ScheduledTasks -ErrorAction Stop
    $powerShell=(Get-Command powershell.exe -ErrorAction Stop).Source
    $arguments='-NoProfile -ExecutionPolicy Bypass -File "{0}" -Root "{1}"' -f $script:TelegramRunnerPath,$script:TelegramRoot
    $action=New-ScheduledTaskAction -Execute $powerShell -Argument $arguments -WorkingDirectory $script:TelegramToolRoot
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent().Name
    $trigger=New-ScheduledTaskTrigger -AtLogOn -User $identity
    $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
    $principal=New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $script:TelegramTaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'BeeForge Telegram Bridge — automatic start at Windows logon (DPAPI protected local integration)' -Force|Out-Null
}

function Get-BeeTelegramConfig {
    Initialize-BeeTelegram
    try{return [IO.File]::ReadAllText($script:TelegramConfigPath,[Text.UTF8Encoding]::new($false))|ConvertFrom-Json}
    catch{throw "Некорректный telegram.json: $($_.Exception.Message)"}
}

function Save-BeeTelegramConfig([Parameter(Mandatory=$true)]$Config) {
    $userId=[string]$Config.allowedUserId;$chatId=[string]$Config.allowedChatId
    if($userId-and$userId-notmatch'^\d+$'){throw 'Telegram User ID должен содержать только цифры'}
    if($chatId-and$chatId-notmatch'^-?\d+$'){throw 'Telegram Chat ID должен быть числом'}
    $port=[int]$Config.bridgePort;if($port-lt1024-or$port-gt65535){throw 'Порт Telegram Bridge должен быть в диапазоне 1024–65535'}
    $minutes=0
    $projects=@($Config.allowedProjects|ForEach-Object{if($_){[IO.Path]::GetFullPath([string]$_)}}|Select-Object -Unique)
    $normalized=[ordered]@{
        enabled=[bool]$Config.enabled;allowedUserId=$userId.Trim();allowedChatId=$chatId.Trim();bridgePort=$port
        summaryIntervalMinutes=$minutes;notifyDelegation=[bool]$Config.notifyDelegation
        notifyCompletion=[bool]$Config.notifyCompletion;notifyErrors=[bool]$Config.notifyErrors
        muted=[bool]$Config.muted;allowedProjects=$projects
        allowPreviouslyOpenedProjects=if($null-eq$Config.allowPreviouslyOpenedProjects){$true}else{[bool]$Config.allowPreviouslyOpenedProjects}
        defaultProjectRoot=if([string]::IsNullOrWhiteSpace([string]$Config.defaultProjectRoot)){'C:\AI\Projects'}else{[IO.Path]::GetFullPath([string]$Config.defaultProjectRoot)}
        pinnedStatus=if($null-eq$Config.pinnedStatus){$true}else{[bool]$Config.pinnedStatus}
        voiceEnabled=if($null-eq$Config.voiceEnabled){$true}else{[bool]$Config.voiceEnabled}
        voicePort=if($null-eq$Config.voicePort){47656}else{[int]$Config.voicePort}
        voiceModel=if([string]::IsNullOrWhiteSpace([string]$Config.voiceModel)){'small'}else{[string]$Config.voiceModel}
        voiceLanguage=if([string]::IsNullOrWhiteSpace([string]$Config.voiceLanguage)){'auto'}else{[string]$Config.voiceLanguage}
    }
    if($normalized.voicePort-lt1024-or$normalized.voicePort-gt65535-or$normalized.voicePort-eq$normalized.bridgePort){throw 'Порт Voice Service должен быть в диапазоне 1024–65535 и отличаться от порта Bridge'}
    Write-BeeTelegramUtf8 $script:TelegramConfigPath ($normalized|ConvertTo-Json -Depth 8)
    return [pscustomobject]$normalized
}

function Set-BeeTelegramToken([Parameter(Mandatory=$true)][string]$Token) {
    $trimmed=$Token.Trim()
    if($trimmed-notmatch'^\d{5,}:[A-Za-z0-9_-]{20,}$'){throw 'Токен Telegram Bot API имеет неверный формат'}
    Add-Type -AssemblyName System.Security
    $plain=[Text.Encoding]::UTF8.GetBytes($trimmed)
    try{$encrypted=[Security.Cryptography.ProtectedData]::Protect($plain,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)}
    finally{[Array]::Clear($plain,0,$plain.Length)}
    [IO.File]::WriteAllBytes($script:TelegramTokenPath,$encrypted)
    Protect-BeeTelegramFile $script:TelegramTokenPath
}

function Get-BeeTelegramToken {
    if(-not(Test-Path -LiteralPath $script:TelegramTokenPath)){return $null}
    Add-Type -AssemblyName System.Security
    $encrypted=[IO.File]::ReadAllBytes($script:TelegramTokenPath)
    $plain=[Security.Cryptography.ProtectedData]::Unprotect($encrypted,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    try{return [Text.Encoding]::UTF8.GetString($plain)}finally{[Array]::Clear($plain,0,$plain.Length)}
}

function Test-BeeTelegramTokenConfigured { return (Test-Path -LiteralPath $script:TelegramTokenPath -PathType Leaf) }

function Test-BeeTelegramConnection {
    $token=Get-BeeTelegramToken;if(-not$token){throw 'Сначала сохраните токен бота'}
    try{$result=Invoke-RestMethod -Method Get -Uri ("https://api.telegram.org/bot{0}/getMe"-f$token) -TimeoutSec 20;if(-not$result.ok){throw 'Telegram вернул ok=false'};return $result.result}
    finally{$token=$null}
}

function Get-BeeTelegramBridgeStatus {
    Initialize-BeeTelegram
    $running=$false;$pidValue=$null
    if(Test-Path -LiteralPath $script:TelegramPidPath){
        $id=0
        if([int]::TryParse(([IO.File]::ReadAllText($script:TelegramPidPath)).Trim(),[ref]$id)){
            $process=Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction SilentlyContinue
            if($process-and$process.Name-eq'node.exe'-and$process.CommandLine-match'telegram-bridge[\\/]v1\.0\.0[\\/]bridge\.mjs'){$running=$true;$pidValue=$id}
        }
    }
    $status=$null
    if(Test-Path -LiteralPath $script:TelegramStatusPath){try{$status=[IO.File]::ReadAllText($script:TelegramStatusPath,[Text.UTF8Encoding]::new($false))|ConvertFrom-Json}catch{}}
    [pscustomobject]@{Running=$running;Pid=$pidValue;State=$(if(-not$running){'stopped'}elseif($status){[string]$status.state}else{'starting'});Message=$(if($running-and$status){[string]$status.message}else{''});UpdatedAt=$(if($status){$status.updatedAt}else{$null});TokenConfigured=(Test-BeeTelegramTokenConfigured)}
}

function Get-BeeTelegramPortOwner([int]$Port) {
    try {
        return Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop|Select-Object -First 1 -ExpandProperty OwningProcess
    } catch { return $null }
}

function Wait-BeeTelegramPortFree([int]$Port,[int]$TimeoutSeconds=6) {
    $deadline=(Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if(-not(Get-BeeTelegramPortOwner $Port)){return $true}
        Start-Sleep -Milliseconds 200
    } while((Get-Date)-lt$deadline)
    return $false
}

function Stop-BeeTelegramBridge {
    $stopped=$false
    $config=Get-BeeTelegramConfig
    Write-BeeTelegramUtf8 $script:TelegramStopMarkerPath ((Get-Date).ToUniversalTime().ToString('o'))
    try{Import-Module ScheduledTasks -ErrorAction Stop;Stop-ScheduledTask -TaskName $script:TelegramTaskName -ErrorAction SilentlyContinue}catch{}
    if(Test-Path -LiteralPath $script:TelegramPidPath){
        $id=0;if([int]::TryParse(([IO.File]::ReadAllText($script:TelegramPidPath)).Trim(),[ref]$id)){
            $process=Get-Process -Id $id -ErrorAction SilentlyContinue
            if($process){Stop-Process -Id $id -Force;$stopped=$true}
        }
        Remove-Item -LiteralPath $script:TelegramPidPath -Force -ErrorAction SilentlyContinue
    }
    if(-not(Wait-BeeTelegramPortFree ([int]$config.bridgePort) 6)){
        $owner=Get-BeeTelegramPortOwner ([int]$config.bridgePort)
        if($owner){
            $process=Get-CimInstance Win32_Process -Filter "ProcessId=$owner" -ErrorAction SilentlyContinue
            if($process-and$process.Name-eq'node.exe'-and$process.CommandLine-match'telegram-bridge[\\/]v1\.0\.0[\\/]bridge\.mjs'){
                Stop-Process -Id $owner -Force -ErrorAction SilentlyContinue
                $stopped=$true
                $null=Wait-BeeTelegramPortFree ([int]$config.bridgePort) 3
            }
        }
    }
    Write-BeeTelegramUtf8 $script:TelegramStatusPath (([ordered]@{state='stopped';message='Bridge stopped';updatedAt=(Get-Date).ToUniversalTime().ToString('o');instances=0})|ConvertTo-Json)
    return [pscustomobject]@{Stopped=$stopped}
}

function Start-BeeTelegramBridge {
    Initialize-BeeTelegram
    $config=Get-BeeTelegramConfig
    if(-not$config.enabled){throw 'Telegram-интеграция выключена'}
    if(-not(Test-BeeTelegramTokenConfigured)){throw 'Токен Telegram не сохранён'}
    if(-not$config.allowedUserId-or-not$config.allowedChatId){throw 'Укажите Telegram User ID и Chat ID'}
    if(-not(Test-Path -LiteralPath (Join-Path $script:TelegramToolRoot 'bridge.mjs'))){throw 'Telegram Bridge не установлен'}
    $existing=Get-BeeTelegramBridgeStatus;if($existing.Running){return $existing}
    $portOwner=Get-BeeTelegramPortOwner ([int]$config.bridgePort)
    if($portOwner){
        $process=Get-CimInstance Win32_Process -Filter "ProcessId=$portOwner" -ErrorAction SilentlyContinue
        if($process-and$process.Name-eq'node.exe'-and$process.CommandLine-match'telegram-bridge[\\/]v1\.0\.0[\\/]bridge\.mjs'){
            Stop-Process -Id $portOwner -Force -ErrorAction SilentlyContinue
            if(-not(Wait-BeeTelegramPortFree ([int]$config.bridgePort) 4)){throw "Порт $($config.bridgePort) не освободился после остановки старого Telegram Bridge"}
        } else {throw "Порт $($config.bridgePort) занят другим процессом PID $portOwner"}
    }
    Remove-Item -LiteralPath $script:TelegramStopMarkerPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $script:TelegramStatusPath -Force -ErrorAction SilentlyContinue
    Install-BeeTelegramScheduledTask
    Start-ScheduledTask -TaskName $script:TelegramTaskName
    $deadline=(Get-Date).AddSeconds(8)
    do{Start-Sleep -Milliseconds 250;$started=Get-BeeTelegramBridgeStatus}while(-not$started.Running-and(Get-Date)-lt$deadline)
    if(-not$started.Running){
        $details=''
        if(Test-Path -LiteralPath $script:TelegramStderrPath){$details=([IO.File]::ReadAllText($script:TelegramStderrPath,[Text.UTF8Encoding]::new($false))).Trim()}
        if($details.Length-gt800){$details=$details.Substring($details.Length-800)}
        throw ('Telegram Bridge завершился сразу после запуска'+$(if($details){': '+$details}else{'. Подробности отсутствуют.'}))
    }
    return $started
}

function Open-BeeTelegramLog {
    Initialize-BeeTelegram
    if(-not(Test-Path -LiteralPath $script:TelegramLogPath)){Write-BeeTelegramUtf8 $script:TelegramLogPath ''}
    Start-Process notepad.exe -ArgumentList ('"'+$script:TelegramLogPath+'"')
}

Export-ModuleMember -Function Get-BeeTelegramPaths,Get-BeeTelegramConfig,Save-BeeTelegramConfig,Set-BeeTelegramToken,Test-BeeTelegramTokenConfigured,Test-BeeTelegramConnection,Get-BeeTelegramBridgeStatus,Start-BeeTelegramBridge,Stop-BeeTelegramBridge,Open-BeeTelegramLog
