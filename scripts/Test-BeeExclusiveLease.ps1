[CmdletBinding()]
param([string]$Root='')
$ErrorActionPreference='Stop'
if(-not$Root){$Root=Split-Path -Parent $PSScriptRoot}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('beeforge-exclusive-lease-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force|Out-Null
try{
    $realStore=[IO.File]::ReadAllText((Join-Path $Root 'config\profiles.json'),[Text.UTF8Encoding]::new($false))|ConvertFrom-Json
    $tempOpenCode=Join-Path $temp 'opencode.json'
    Copy-Item -LiteralPath ([string]$realStore.openCodeConfigPath) -Destination $tempOpenCode
    $realStore.openCodeConfigPath=$tempOpenCode
    $tempStore=Join-Path $temp 'profiles.json'
    [IO.File]::WriteAllText($tempStore,($realStore|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
    $env:BEEFORGE_PROFILE_STORE=$tempStore
    $env:BEEFORGE_REMOTE_CONFIG=Join-Path $temp 'remote-access.json'
    Import-Module (Join-Path $Root 'scripts\BeeLlamaManager.Core.psm1') -Force
    $profile=Get-BeeProfile
    if((Get-BeeProfileConnectionMode $profile)-ne'LocalHost'){throw 'Exclusive lease test requires the active LocalHost profile'}

    [IO.File]::WriteAllText($env:BEEFORGE_REMOTE_CONFIG,'{"Enabled":true,"Managed":true}',[Text.UTF8Encoding]::new($false))
    if(-not(Test-BeeLocalModelLeased)){throw 'Enabled managed access was not recognized as an exclusive remote lease'}
    if((Get-BeeOpenCodeProfileBaseUrl $profile)-ne'http://127.0.0.1:1/v1'){throw 'Local OpenCode endpoint was not blocked'}
    Update-BeeOpenCode $profile|Out-Null
    $leasedConfig=[IO.File]::ReadAllText($tempOpenCode,[Text.UTF8Encoding]::new($false))|ConvertFrom-Json
    if([string]$leasedConfig.provider.beellama.options.baseURL-ne'http://127.0.0.1:1/v1'){throw 'OpenCode config did not receive the blocked endpoint'}
    $launcherBlocked=$false
    try{& (Join-Path $Root 'scripts\Start-OpenCode.ps1')}catch{$launcherBlocked=$true}
    if(-not$launcherBlocked){throw 'The local OpenCode launcher was not blocked during a remote lease'}
    $benchmarkBlocked=$false
    try{Start-BeeBenchmark -ProfileId $profile.id|Out-Null}catch{$benchmarkBlocked=$true}
    if(-not$benchmarkBlocked){throw 'Benchmark unexpectedly started during a remote lease'}

    [IO.File]::WriteAllText($env:BEEFORGE_REMOTE_CONFIG,'{"Enabled":false,"Managed":true}',[Text.UTF8Encoding]::new($false))
    if(Test-BeeLocalModelLeased){throw 'Disabled access remained leased'}
    Update-BeeOpenCode $profile|Out-Null
    $localConfig=[IO.File]::ReadAllText($tempOpenCode,[Text.UTF8Encoding]::new($false))|ConvertFrom-Json
    $expected=Get-BeeProfileApiBaseUrl $profile
    if([string]$localConfig.provider.beellama.options.baseURL-ne$expected){throw "Local OpenCode endpoint was not restored: $($localConfig.provider.beellama.options.baseURL)"}
    Write-Host 'Exclusive remote lease checks: PASS' -ForegroundColor Green
}finally{
    Remove-Item Env:BEEFORGE_PROFILE_STORE,Env:BEEFORGE_REMOTE_CONFIG -ErrorAction SilentlyContinue
    Remove-Module BeeLlamaManager.Core -Force -ErrorAction SilentlyContinue
    if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}
}
