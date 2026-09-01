[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$McpId,[int]$TimeoutSec=10)

$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'BeeForgeTeam.Core.psm1') -Force
try{Invoke-BeeMcpHandshake -McpId $McpId -TimeoutSec $TimeoutSec;exit 0}catch{exit 1}
