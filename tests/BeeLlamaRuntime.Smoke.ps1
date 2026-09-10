Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'scripts\BeeLlamaManager.Core.psm1') -Force

$p = Get-BeeNewProfileTemplate
$expectedSuffix = 'runtime\beellama-v0.4.6-cuda13.3\llama-server.exe'
if (-not ([string]$p.serverPath).EndsWith($expectedSuffix,[StringComparison]::OrdinalIgnoreCase)) {
    throw "New profile runtime default is not BeeLlama v0.4.6 CUDA 13.3: $($p.serverPath)"
}

$templatePath = Join-Path $root 'config\templates\profiles.example.json'
$template = [IO.File]::ReadAllText($templatePath,[Text.UTF8Encoding]::new($false))
if ($template -notmatch 'beellama-v0\.4\.6-cuda13\.3') { throw 'Profile template does not reference BeeLlama v0.4.6 CUDA 13.3' }
if ($template -match 'beellama-v0\.4\.3-cuda13\.1') { throw 'Profile template still references BeeLlama v0.4.3 CUDA 13.1' }

$installerPath = Join-Path $root 'scripts\Install-BeeLlamaRuntime.ps1'
if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) { throw 'Install-BeeLlamaRuntime.ps1 is missing' }
$installer = [IO.File]::ReadAllText($installerPath,[Text.UTF8Encoding]::new($false))
foreach ($needle in @('v0.4.6','13.3','releases/tags','digest','UpdateProfiles')) {
    if ($installer -notmatch [regex]::Escape($needle)) { throw "Runtime installer is missing expected token: $needle" }
}

Write-Host 'BeeLlama runtime smoke test passed.'
