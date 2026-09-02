Set-StrictMode -Version 2.0
$script:BeeRoot = Split-Path $PSScriptRoot -Parent
$script:RemoteConfigPath = if($env:BEEFORGE_REMOTE_CONFIG){[IO.Path]::GetFullPath($env:BEEFORGE_REMOTE_CONFIG)}else{Join-Path $script:BeeRoot 'config\remote-access.json'}
Import-Module (Join-Path $PSScriptRoot 'BeeLlamaManager.Core.psm1')

function Get-BeeTailscaleExecutable {
    $command = Get-Command tailscale.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $default = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
    if (Test-Path -LiteralPath $default -PathType Leaf) { return $default }
    throw 'Tailscale не установлен. Установите его и войдите в тот же tailnet на обоих компьютерах.'
}

function Invoke-BeeTailscale([string[]]$Arguments,[switch]$AllowFailure) {
    $executable = Get-BeeTailscaleExecutable
    $output = & $executable @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -and -not $AllowFailure) { throw "tailscale $($Arguments -join ' ') завершился с ошибкой: $($output.Trim())" }
    return $output.Trim()
}

function Get-BeeTailscaleStatus {
    $result = [ordered]@{ Installed=$false; Connected=$false; BackendState='Missing'; DnsName=''; Ip=''; Message='Tailscale не установлен' }
    try {
        [void](Get-BeeTailscaleExecutable); $result.Installed=$true
        $data = Invoke-BeeTailscale @('status','--json') | ConvertFrom-Json
        $result.BackendState=[string]$data.BackendState
        $result.Connected=($result.BackendState -eq 'Running')
        if ($data.Self) {
            $result.DnsName=([string]$data.Self.DNSName).TrimEnd('.')
            $result.Ip=[string]@($data.TailscaleIPs | Where-Object { $_ -match '^100\.' } | Select-Object -First 1)
        }
        $result.Message=if($result.Connected){'Tailscale подключён'}else{"Tailscale: $($result.BackendState)"}
    } catch { $result.Message=$_.Exception.Message }
    return [pscustomobject]$result
}

function ConvertTo-BeeCanonicalJson($Value){return($Value|ConvertTo-Json -Depth 100 -Compress)}

function Test-BeeTailscaleServeConfiguration($Value) {
    if ($null -eq $Value) { return $false }
    return (@($Value.PSObject.Properties).Count -gt 0)
}

function Test-BeeRemoteAccessCanDisable($State) {
    if ($null -eq $State) { return $false }
    # Enabled marks a route that BeeForge created and recorded. This also lets
    # the user clear a stale saved state after the route disappeared externally,
    # while never offering to remove an unrelated Tailscale Serve setup.
    return ([bool]$State.Managed -and [bool]$State.Enabled)
}

function Get-BeeRemoteAccessState {
    $state = [ordered]@{ Enabled=$false; Managed=$false; Port=$null; DnsName=''; BaseUrl=''; ServeStatusJson=''; ServeConfigured=$false; CurrentServeStatusJson=''; Message='Удалённый доступ выключен' }
    if (Test-Path -LiteralPath $script:RemoteConfigPath -PathType Leaf) {
        try {
            $saved=[IO.File]::ReadAllText($script:RemoteConfigPath,[Text.UTF8Encoding]::new($false))|ConvertFrom-Json
            foreach($name in @('Enabled','Managed','Port','DnsName','BaseUrl','ServeStatusJson')) { if($saved.PSObject.Properties[$name]){$state[$name]=$saved.$name} }
        } catch { $state.Message="Некорректная локальная конфигурация: $($_.Exception.Message)" }
    }
    try {
        $serveText=Invoke-BeeTailscale @('serve','status','--json') -AllowFailure
        if($serveText){$serve=$serveText|ConvertFrom-Json;$state.ServeConfigured=Test-BeeTailscaleServeConfiguration $serve;$state.CurrentServeStatusJson=ConvertTo-BeeCanonicalJson $serve}
    } catch {}
    if($state.Enabled){$state.Message=if($state.ServeConfigured){'Tailscale Serve включён'}else{'Настройка сохранена, но Tailscale Serve не активен'}}
    elseif($state.ServeConfigured){$state.Message='Обнаружена сторонняя конфигурация Tailscale Serve. BeeForge не будет её изменять.'}
    else{$state.Message='Доступ с ноутбука выключен. Модель доступна только на этом ПК через 127.0.0.1.'}
    return [pscustomobject]$state
}

function Save-BeeRemoteAccessState($State) {
    $directory=Split-Path $script:RemoteConfigPath -Parent
    if(-not(Test-Path -LiteralPath $directory)){New-Item -ItemType Directory -Path $directory -Force|Out-Null}
    $temp="$script:RemoteConfigPath.tmp"
    [IO.File]::WriteAllText($temp,($State|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temp -Destination $script:RemoteConfigPath -Force
}

function Start-BeeTailscaleServe([int]$Port,[int]$TimeoutSec=20) {
    $executable=Get-BeeTailscaleExecutable
    $tempRoot=Join-Path ([IO.Path]::GetTempPath()) ('beeforge-tailscale-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempRoot -Force|Out-Null
    $stdout=Join-Path $tempRoot 'stdout.txt';$stderr=Join-Path $tempRoot 'stderr.txt'
    try{
        $process=Start-Process -FilePath $executable -ArgumentList @('serve','--bg',[string]$Port) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden
        try{$process|Wait-Process -Timeout $TimeoutSec -ErrorAction Stop}catch{}
        if(-not$process.HasExited){
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            $details=((Get-Content -LiteralPath $stdout,$stderr -Raw -ErrorAction SilentlyContinue)-join[Environment]::NewLine).Trim()
            throw "Tailscale Serve ожидает однократного разрешения HTTPS в tailnet. Откройте ссылку из сообщения ниже, подтвердите Serve и повторите включение.`n$details"
        }
        $details=((Get-Content -LiteralPath $stdout,$stderr -Raw -ErrorAction SilentlyContinue)-join[Environment]::NewLine).Trim()
        if($process.ExitCode-ne0){throw "Не удалось включить Tailscale Serve: $details"}
        return $details
    }finally{if(Test-Path -LiteralPath $tempRoot){Remove-Item -LiteralPath $tempRoot -Recurse -Force}}
}

function Enable-BeeRemoteAccess([Parameter(Mandatory=$true)]$Profile) {
    if((Get-BeeProfileConnectionMode $Profile)-ne'LocalHost'){throw 'Tailscale Serve включается только для локального профиля основного ПК.'}
    if([string]$Profile.host -notin @('127.0.0.1','localhost')){throw 'BeeLlama должен оставаться привязанным к 127.0.0.1 или localhost.'}
    $tailscale=Get-BeeTailscaleStatus
    if(-not$tailscale.Connected-or-not$tailscale.DnsName){throw $tailscale.Message}
    $existing=Get-BeeRemoteAccessState
    if($existing.ServeConfigured-and-not$existing.Managed){throw 'На этом ПК уже есть чужая конфигурация Tailscale Serve. BeeForge не будет её перезаписывать.'}
    [void](Start-BeeTailscaleServe -Port ([int]$Profile.port))
    try {
        $baseUrl="https://$($tailscale.DnsName)/v1"
        $serve=Invoke-BeeTailscale @('serve','status','--json')|ConvertFrom-Json
        $state=[ordered]@{Enabled=$true;Managed=$true;Port=[int]$Profile.port;DnsName=$tailscale.DnsName;BaseUrl=$baseUrl;ServeStatusJson=(ConvertTo-BeeCanonicalJson $serve);UpdatedAt=(Get-Date).ToString('o')}
        Save-BeeRemoteAccessState $state
        # The lease becomes active before OpenCode is synchronized, so its
        # local provider is atomically replaced with an unreachable loopback URL.
        Update-BeeOpenCode $Profile -Force | Out-Null
        return Get-BeeRemoteAccessState
    } catch {
        try { [void](Invoke-BeeTailscale @('serve','reset') -AllowFailure) } catch {}
        Save-BeeRemoteAccessState ([ordered]@{Enabled=$false;Managed=$true;Port=$null;DnsName='';BaseUrl='';ServeStatusJson='';UpdatedAt=(Get-Date).ToString('o')})
        try { Update-BeeOpenCode $Profile -Force | Out-Null } catch {}
        throw
    }
}

function Disable-BeeRemoteAccess {
    $state=Get-BeeRemoteAccessState
    if($state.ServeConfigured){
        if(-not$state.Managed){throw 'Tailscale Serve не был создан BeeForge; автоматическое удаление запрещено.'}
        if(-not$state.ServeStatusJson-or$state.CurrentServeStatusJson-ne$state.ServeStatusJson){throw 'Конфигурация Tailscale Serve изменилась после включения BeeForge. Автоматическое удаление запрещено, чтобы не затронуть чужие маршруты.'}
        [void](Invoke-BeeTailscale @('serve','reset'))
    }
    Save-BeeRemoteAccessState ([ordered]@{Enabled=$false;Managed=$true;Port=$null;DnsName='';BaseUrl='';ServeStatusJson='';UpdatedAt=(Get-Date).ToString('o')})
    try {
        $profile=Get-BeeProfile
        if((Get-BeeProfileConnectionMode $profile)-eq'LocalHost'){Update-BeeOpenCode $profile -Force|Out-Null}
    } catch {
        throw "Удалённый маршрут выключен, но не удалось восстановить локальный OpenCode endpoint: $($_.Exception.Message)"
    }
    return Get-BeeRemoteAccessState
}

function Get-BeeRemoteClientInstallCommand([Parameter(Mandatory=$true)]$Profile) {
    $state=Get-BeeRemoteAccessState
    if(-not$state.Enabled-or-not$state.BaseUrl){throw 'Сначала включите Tailscale Serve.'}
    $vision=($Profile.PSObject.Properties['visionEnabled']-and[bool]$Profile.visionEnabled)
    $parts=@("pwsh -File .\scripts\Install-BeeForge.ps1 -Mode RemoteClient -ConfigureOpenCode",("-RemoteBaseUrl `"{0}`""-f$state.BaseUrl),("-RemoteModelAlias `"{0}`""-f$Profile.alias),("-RemoteContext {0}"-f[int]$Profile.context),("-RemoteOutput {0}"-f[int]$Profile.openCodeOutput))
    if($vision){$parts+='-RemoteVision'}
    return ($parts-join' ')
}

Export-ModuleMember -Function Get-BeeTailscaleStatus,Get-BeeRemoteAccessState,Test-BeeTailscaleServeConfiguration,Test-BeeRemoteAccessCanDisable,Enable-BeeRemoteAccess,Disable-BeeRemoteAccess,Get-BeeRemoteClientInstallCommand
