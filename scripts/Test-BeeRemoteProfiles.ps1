[CmdletBinding()]
param([string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('beeforge-remote-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force|Out-Null
try{
    $openCodePath=Join-Path $temp 'opencode.json'
    Copy-Item -LiteralPath (Join-Path $Root 'opencode\opencode.template.json') -Destination $openCodePath
    $template=Get-Content -LiteralPath (Join-Path $Root 'config\templates\profiles.example.json') -Raw|ConvertFrom-Json
    $legacy=$template.profiles|Select-Object -First 1
    $legacy.PSObject.Properties.Remove('connectionMode');$legacy.PSObject.Properties.Remove('remoteBaseUrl')
    $remote=($legacy|ConvertTo-Json -Depth 30|ConvertFrom-Json)
    $remote.id='remote-test';$remote.name='Remote test';$remote.alias='Q2';$remote.context=162000;$remote.openCodeOutput=65528
    $remote.modelPath='';$remote.serverPath=''
    $remote|Add-Member -NotePropertyName connectionMode -NotePropertyValue RemoteClient
    $remote|Add-Member -NotePropertyName remoteBaseUrl -NotePropertyValue 'https://desktop.example.ts.net'
    $store=[pscustomobject]@{schemaVersion=1;activeProfileId='legacy';lastGoodProfileId='legacy';modelRoots=@();openCodeConfigPath=$openCodePath;profiles=@($legacy,$remote)}
    $storePath=Join-Path $temp 'profiles.json'
    [IO.File]::WriteAllText($storePath,($store|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
    $env:BEEFORGE_PROFILE_STORE=$storePath
    Import-Module (Join-Path $Root 'scripts\BeeLlamaManager.Core.psm1') -Force
    $loaded=Get-BeeProfileStore
    if((Get-BeeProfileConnectionMode $loaded.profiles[0])-ne'LocalHost'){throw 'Legacy profile was not migrated to LocalHost'}
    if($loaded.profiles[0].remoteBaseUrl-ne''){throw 'Legacy remoteBaseUrl default is invalid'}
    $remoteLoaded=Get-BeeProfile 'remote-test'
    $validation=Test-BeeProfile $remoteLoaded
    if(-not$validation.Valid){throw "Remote profile validation failed: $($validation.Errors -join ', ')"}
    if((Get-BeeProfileApiBaseUrl $remoteLoaded)-ne'https://desktop.example.ts.net/v1'){throw 'Remote URL normalization failed'}
    Update-BeeOpenCode $remoteLoaded|Out-Null
    $config=[IO.File]::ReadAllText($openCodePath,[Text.UTF8Encoding]::new($false))|ConvertFrom-Json
    if($config.provider.beellama.options.baseURL-ne'https://desktop.example.ts.net/v1'){throw 'OpenCode remote baseURL was not updated'}
    if($config.model-ne'beellama/Q2'){throw 'OpenCode remote model was not selected'}
    foreach($agent in $config.agent.PSObject.Properties){if($agent.Value.model-ne'beellama/Q2'){throw "Agent $($agent.Name) was not synced"}}
    $before=@(Get-Process -Name llama-server -ErrorAction SilentlyContinue).Count
    $connection=Test-BeeRemoteConnection $remoteLoaded -TimeoutSec 1
    $after=@(Get-Process -Name llama-server -ErrorAction SilentlyContinue).Count
    if($connection.Ready){throw 'Unreachable test endpoint unexpectedly reported READY'}
    if($before-ne$after){throw 'Remote connection check changed local llama-server processes'}
    Write-Host 'Remote profile checks: PASS' -ForegroundColor Green
}finally{
    Remove-Item Env:BEEFORGE_PROFILE_STORE -ErrorAction SilentlyContinue
    Remove-Module BeeLlamaManager.Core -Force -ErrorAction SilentlyContinue
    if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}
}
