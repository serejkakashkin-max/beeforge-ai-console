[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProfileStore,
    [Parameter(Mandatory=$true)][string]$ProfileId
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'BeeLlamaManager.Core.psm1') -Force
$json = [IO.File]::ReadAllText([IO.Path]::GetFullPath($ProfileStore), [Text.UTF8Encoding]::new($false))
$store = $json | ConvertFrom-Json
$profile = @($store.profiles | Where-Object { [string]$_.id -ceq $ProfileId }) | Select-Object -First 1
if (-not $profile) { throw 'Requested profile was not found' }
$mode = Get-BeeProfileConnectionMode $profile
if ($mode -eq 'RemoteClient') {
    [pscustomobject]@{ mode=$mode; serverPath=''; alias=[string]$profile.alias; arguments=@() } | ConvertTo-Json -Depth 8 -Compress
    return
}
[pscustomobject]@{
    mode=$mode
    serverPath=[string]$profile.serverPath
    alias=[string]$profile.alias
    arguments=@(Get-BeeArguments $profile)
} | ConvertTo-Json -Depth 8 -Compress
