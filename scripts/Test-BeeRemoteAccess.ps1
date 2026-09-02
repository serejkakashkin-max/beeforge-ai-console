[CmdletBinding()]
param([string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('beeforge-serve-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force|Out-Null
try{
    $env:BEEFORGE_REMOTE_CONFIG=Join-Path $temp 'remote-access.json'
    Import-Module (Join-Path $Root 'scripts\BeeLlamaManager.Core.psm1') -Force
    Import-Module (Join-Path $Root 'scripts\BeeForgeRemote.Core.psm1') -Force
    if(-not(Get-Command Test-BeeTailscaleServeConfiguration -ErrorAction SilentlyContinue)){throw 'Serve configuration detector is not exported'}
    if(Test-BeeTailscaleServeConfiguration (ConvertFrom-Json '{}')){throw 'Empty Serve JSON must be detected as disabled'}
    if(-not(Test-BeeTailscaleServeConfiguration (ConvertFrom-Json '{"TCP":{"443":{"HTTPS":true}}}'))){throw 'Non-empty Serve JSON must be detected as enabled'}
    if(Test-BeeRemoteAccessCanDisable ([pscustomobject]@{Managed=$false;ServeConfigured=$true;Enabled=$true})){throw 'Foreign Serve configuration must not be removable'}
    if(-not(Test-BeeRemoteAccessCanDisable ([pscustomobject]@{Managed=$true;ServeConfigured=$true;Enabled=$true}))){throw 'Active BeeForge Serve configuration must be removable'}
    if(-not(Test-BeeRemoteAccessCanDisable ([pscustomobject]@{Managed=$true;ServeConfigured=$false;Enabled=$true}))){throw 'Stale BeeForge access state must be clearable'}
    if(Test-BeeRemoteAccessCanDisable ([pscustomobject]@{Managed=$true;ServeConfigured=$false;Enabled=$false})){throw 'Already disabled state must not enable the disable action'}
    if(Test-BeeRemoteAccessCanDisable ([pscustomobject]@{Managed=$true;ServeConfigured=$true;Enabled=$false})){throw 'Unrecorded Serve configuration must not be removable'}
    $tailscale=Get-BeeTailscaleStatus
    if(-not$tailscale.Installed){throw 'Tailscale status detection failed on the host'}
    [IO.File]::WriteAllText($env:BEEFORGE_REMOTE_CONFIG,([ordered]@{Enabled=$true;Managed=$true;Port=8080;DnsName='desktop.example.ts.net';BaseUrl='https://desktop.example.ts.net/v1'}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    $profile=[pscustomobject]@{connectionMode='LocalHost';alias='Q2';context=190000;openCodeOutput=65528;visionEnabled=$true}
    $command=Get-BeeRemoteClientInstallCommand $profile
    foreach($expected in @('-Mode RemoteClient','https://desktop.example.ts.net/v1','-RemoteModelAlias "Q2"','-RemoteContext 190000','-RemoteVision')){if(-not$command.Contains($expected)){throw "Install command is missing: $expected"}}
    $source=Get-Content -LiteralPath (Join-Path $Root 'scripts\BeeForgeRemote.Core.psm1') -Raw
    if($source-match"Invoke-BeeTailscale @\('funnel'"){throw 'Remote module must never configure Tailscale Funnel'}
    Write-Host 'Remote access checks: PASS' -ForegroundColor Green
}finally{
    Remove-Item Env:BEEFORGE_REMOTE_CONFIG -ErrorAction SilentlyContinue
    Remove-Module BeeForgeRemote.Core,BeeLlamaManager.Core -Force -ErrorAction SilentlyContinue
    if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}
}
