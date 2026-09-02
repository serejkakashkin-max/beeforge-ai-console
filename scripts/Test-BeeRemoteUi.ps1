[CmdletBinding()]
param([string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('beeforge-ui-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force|Out-Null
try{
    $template=Get-Content -LiteralPath (Join-Path $Root 'config\templates\profiles.example.json') -Raw|ConvertFrom-Json
    $profile=$template.profiles|Select-Object -First 1
    $profile.connectionMode='RemoteClient';$profile.remoteBaseUrl='https://desktop.example.ts.net/v1';$profile.modelPath='';$profile.serverPath='';$profile.id='remote-ui';$profile.name='Remote UI';$profile.alias='Q2';$profile.context=190000;$profile.openCodeOutput=65528;$profile.visionEnabled=$true
    $store=[pscustomobject]@{schemaVersion=1;activeProfileId=$profile.id;lastGoodProfileId='';modelRoots=@();openCodeConfigPath=(Join-Path $temp 'opencode.json');profiles=@($profile)}
    $env:BEEFORGE_PROFILE_STORE=Join-Path $temp 'profiles.json'
    $env:BEEFORGE_REMOTE_CONFIG=Join-Path $temp 'remote-access.json'
    $env:BEEFORGE_REMOTE_SMOKE_TEST='1'
    [IO.File]::WriteAllText($env:BEEFORGE_PROFILE_STORE,($store|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
    & (Join-Path $Root 'ui\BeeLlama-Manager.ps1')
    Write-Host 'Remote client UI checks: PASS' -ForegroundColor Green
}finally{
    Remove-Item Env:BEEFORGE_PROFILE_STORE,Env:BEEFORGE_REMOTE_CONFIG,Env:BEEFORGE_REMOTE_SMOKE_TEST -ErrorAction SilentlyContinue
    if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}
}
