[CmdletBinding()]
param([string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('beeforge-install-test-'+[guid]::NewGuid().ToString('N'))
$copy=Join-Path $temp 'BeeForge AI Console';$openCode=Join-Path $temp 'opencode';$projects=Join-Path $temp 'projects'
try{
    New-Item -ItemType Directory -Path $copy -Force|Out-Null
    foreach($name in @('scripts','config','opencode','tools','assets')){Copy-Item -LiteralPath (Join-Path $Root $name) -Destination (Join-Path $copy $name) -Recurse -Force}
    Copy-Item -LiteralPath (Join-Path $Root 'BEEFORGE-AI.cmd') -Destination $copy
    & (Join-Path $copy 'scripts\Install-BeeForge.ps1') -Mode RemoteClient -RemoteBaseUrl 'https://desktop.example.ts.net' -RemoteModelAlias Q2 -RemoteContext 162000 -RemoteOutput 65528 -RemoteVision -ProjectRoot $projects -OpenCodeRoot $openCode -ConfigureOpenCode -SkipDependencies -Force
    if($LASTEXITCODE-ne0){throw "Remote installer exited with $LASTEXITCODE"}
    $profiles=Get-Content -LiteralPath (Join-Path $copy 'config\profiles.json') -Raw|ConvertFrom-Json
    $profile=$profiles.profiles|Select-Object -First 1
    if($profile.connectionMode-ne'RemoteClient'-or$profile.modelPath-or$profile.serverPath){throw 'Remote profile was not created correctly'}
    $telegram=Get-Content -LiteralPath (Join-Path $copy 'config\telegram.json') -Raw|ConvertFrom-Json
    if($telegram.enabled){throw 'Telegram must be disabled for RemoteClient'}
    $config=Get-Content -LiteralPath (Join-Path $openCode 'opencode.json') -Raw|ConvertFrom-Json
    if($config.provider.beellama.options.baseURL-ne'https://desktop.example.ts.net/v1'){throw 'Remote provider endpoint is invalid'}
    if(Test-Path -LiteralPath (Join-Path $openCode 'plugin\beeforge-telegram.js')){throw 'Telegram plugin must not be installed on RemoteClient'}
    Write-Host 'Remote installer checks: PASS' -ForegroundColor Green
}finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
