[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$OpenCodeArguments
)

$ErrorActionPreference = 'Stop'
$coreModule = Join-Path $PSScriptRoot 'BeeLlamaManager.Core.psm1'
Import-Module $coreModule -Force
$activeProfile = Get-BeeProfile
if ((Get-BeeProfileConnectionMode $activeProfile) -eq 'LocalHost' -and (Test-BeeLocalModelLeased)) {
    throw 'Модель передана ноутбуку. Выключите удалённый доступ в BeeForge, чтобы открыть локальный OpenCode.'
}
$openCodeExe = Join-Path $env:LOCALAPPDATA 'Programs\@opencode-aidesktop\OpenCode.exe'
$openCodeTemp = Join-Path $env:LOCALAPPDATA 'Temp\opencode'

if (-not (Test-Path -LiteralPath $openCodeExe -PathType Leaf)) {
    throw "OpenCode executable was not found: $openCodeExe"
}

if (-not (Test-Path -LiteralPath $openCodeTemp -PathType Container)) {
    New-Item -ItemType Directory -Path $openCodeTemp -Force | Out-Null
}

# Child processes, including shell tools and MCP servers, inherit this isolated
# temporary directory. This avoids granting agents access to the whole user TEMP.
$env:TEMP = $openCodeTemp
$env:TMP = $openCodeTemp

$start = @{
    FilePath = $openCodeExe
    WorkingDirectory = Split-Path $openCodeExe -Parent
}
if ($OpenCodeArguments -and $OpenCodeArguments.Count -gt 0) {
    $start.ArgumentList = $OpenCodeArguments
}

Start-Process @start
