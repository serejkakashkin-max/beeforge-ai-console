[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Status','Start','Stop','ConnectRemote')][string]$Action,
    [Parameter(Mandatory=$true)][string]$ProfileStore,
    [string]$ProfileId
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if ($Action -ne 'Status' -and [string]::IsNullOrWhiteSpace($ProfileId)) {
    throw 'A profile ID is required for this action.'
}
$env:BEEFORGE_PROFILE_STORE = [IO.Path]::GetFullPath($ProfileStore)
Import-Module (Join-Path $PSScriptRoot 'BeeLlamaManager.Core.psm1') -Force

switch ($Action) {
    'Status' {
        $result = Get-BeeServerStatus
        $result | Add-Member -NotePropertyName Leased -NotePropertyValue ([bool](Test-BeeLocalModelLeased)) -Force
    }
    'Start' {
        $profile = Get-BeeProfile $ProfileId
        if ((Get-BeeProfileConnectionMode $profile) -ne 'LocalHost') { throw 'A remote client cannot start a local server.' }
        if (Test-BeeLocalModelLeased) { throw 'The model is leased to a remote client. Disable remote access first.' }
        $result = Start-BeeServer $ProfileId
    }
    'Stop' {
        $profile = Get-BeeProfile $ProfileId
        if ((Get-BeeProfileConnectionMode $profile) -ne 'LocalHost') { throw 'A remote client cannot stop the inference host.' }
        if (Test-BeeLocalModelLeased) { throw 'The model is leased to a remote client. Disable remote access first.' }
        $result = Stop-BeeServer
    }
    'ConnectRemote' {
        $profile = Get-BeeProfile $ProfileId
        if ((Get-BeeProfileConnectionMode $profile) -ne 'RemoteClient') { throw 'The selected profile is not a remote client.' }
        $result = Connect-BeeRemoteProfile $ProfileId
    }
}
$result | ConvertTo-Json -Depth 8 -Compress
