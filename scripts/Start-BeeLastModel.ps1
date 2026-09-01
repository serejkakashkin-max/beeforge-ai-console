[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$StatusPath,
    [string]$ProfileId='',
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
$lockPath = Join-Path (Split-Path $StatusPath -Parent) 'model-start.lock'
$lock = $null

function Write-ModelStatus([string]$State,[string]$Message,$Server=$null,[string]$ProfileId='') {
    $directory = Split-Path $StatusPath -Parent
    if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $value = [ordered]@{
        state=$State;message=$Message;profileId=$ProfileId
        profile=if($Server){[string]$Server.Profile}else{''}
        ready=if($Server){[bool]$Server.Ready}else{$false}
        running=if($Server){[bool]$Server.Running}else{$false}
        pid=if($Server){$Server.Pid}else{$null}
        workerPid=$PID;updatedAt=(Get-Date).ToString('o')
    }
    $temp="$StatusPath.$PID.tmp"
    [IO.File]::WriteAllText($temp,($value|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temp -Destination $StatusPath -Force
}

try {
    $lockDirectory=Split-Path $lockPath -Parent
    if (-not (Test-Path -LiteralPath $lockDirectory)) { New-Item -ItemType Directory -Path $lockDirectory -Force | Out-Null }
    $lock = [IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    Import-Module (Join-Path $PSScriptRoot 'BeeLlamaManager.Core.psm1') -Force
    $store = Get-BeeProfileStore
    $profileId = if(-not [string]::IsNullOrWhiteSpace($ProfileId)){$ProfileId}elseif(-not [string]::IsNullOrWhiteSpace([string]$store.lastGoodProfileId)){[string]$store.lastGoodProfileId}else{[string]$store.activeProfileId}
    if ([string]::IsNullOrWhiteSpace($profileId)) { throw 'В BeeForge нет последнего активного профиля.' }
    $profile = Get-BeeProfile $profileId
    if($ValidateOnly){Write-ModelStatus 'validated' "Профиль проверен: $($profile.name)" $null $profileId;exit 0}
    $status = Get-BeeServerStatus
    if ($status.Ready -and [string]::Equals([string]$status.Profile,[string]$profile.name,[StringComparison]::OrdinalIgnoreCase)) { Write-ModelStatus 'ready' 'Выбранная модель уже была готова.' $status $profileId; exit 0 }
    if ($status.Running -and -not [string]::Equals([string]$status.Profile,[string]$profile.name,[StringComparison]::OrdinalIgnoreCase)) {
        [void](Stop-BeeServer)
        $status=Get-BeeServerStatus
    }
    if ($status.Running) {
        Write-ModelStatus 'loading' 'Существующий сервер загружает модель.' $status $profileId
        for($attempt=0;$attempt-lt120;$attempt++){
            Start-Sleep -Seconds 1
            $status=Get-BeeServerStatus
            if($status.Ready){Write-ModelStatus 'ready' 'Модель готова.' $status $profileId;exit 0}
            if(-not$status.Running){break}
        }
        throw 'Существующий сервер не стал READY за 120 секунд.'
    }
    Write-ModelStatus 'loading' "Запускается последний профиль: $($profile.name)" $status $profileId
    $status = Start-BeeServer -ProfileId $profileId
    Write-ModelStatus 'ready' 'Последняя активная модель готова.' $status $profileId
    exit 0
} catch {
    try { Write-ModelStatus 'error' $_.Exception.Message $null $profileId } catch {}
    exit 1
} finally {
    if($lock){$lock.Dispose()}
    try { Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue } catch {}
}
