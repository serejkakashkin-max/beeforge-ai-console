[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('TelegramStatus','TelegramStart','TelegramStop','RemoteStatus','RemoteEnable','RemoteDisable','RemoteInstallCommand','FullAccessStatus','FullAccessEnable','FullAccessDisable','SerenaProjects')][string]$Action,
    [Parameter(Mandatory)][string]$ProfileStore,
    [string]$ProfileId
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$WarningPreference='SilentlyContinue'
$env:BEEFORGE_PROFILE_STORE=[IO.Path]::GetFullPath($ProfileStore)
# Read without migrating or saving profiles. Services must not silently rewrite user state.
$store=[IO.File]::ReadAllText($env:BEEFORGE_PROFILE_STORE)|ConvertFrom-Json
$profile=@($store.profiles|Where-Object {$_.id -eq $ProfileId})|Select-Object -First 1
$remote=$profile -and $profile.PSObject.Properties['connectionMode'] -and $profile.connectionMode -eq 'RemoteClient'
if($Action -in @('TelegramStart','RemoteEnable','RemoteDisable','RemoteInstallCommand')){
    if(-not $profile){throw 'Select a profile first.'}
    if($remote){throw 'Host operations are not available to RemoteClient.'}
}
switch -Wildcard ($Action) {
    'Telegram*' {
        Import-Module (Join-Path $PSScriptRoot 'BeeForgeTelegram.Core.psm1') -Force
        if($Action -eq 'TelegramStart'){$null=Start-BeeTelegramBridge}
        if($Action -eq 'TelegramStop'){$null=Stop-BeeTelegramBridge}
        $s=Get-BeeTelegramBridgeStatus
        $result=[ordered]@{Running=[bool]$s.Running;Pid=$s.Pid;State=[string]$s.State;TokenConfigured=[bool]$s.TokenConfigured}
    }
    'Remote*' {
        Import-Module (Join-Path $PSScriptRoot 'BeeForgeRemote.Core.psm1') -Force
        if($Action -eq 'RemoteEnable'){$null=Enable-BeeRemoteAccess $profile}
        if($Action -eq 'RemoteDisable'){$null=Disable-BeeRemoteAccess}
        if($Action -eq 'RemoteInstallCommand'){
            $result=[ordered]@{Command=[string](Get-BeeRemoteClientInstallCommand $profile)}
        }else{
            $t=Get-BeeTailscaleStatus;$s=Get-BeeRemoteAccessState
            $result=[ordered]@{Installed=[bool]$t.Installed;Connected=[bool]$t.Connected;Enabled=[bool]$s.Enabled;Managed=[bool]$s.Managed;ServeConfigured=[bool]$s.ServeConfigured;BaseUrl=[string]$s.BaseUrl;DnsName=[string]$t.DnsName}
        }
    }
    'FullAccess*' {
        # Team module owns backups and role-scoped tool restrictions. Its store is fixed at the installation root.
        $canonical=[IO.Path]::GetFullPath((Join-Path (Split-Path $PSScriptRoot -Parent) 'config/profiles.json'))
        if($canonical -ne $env:BEEFORGE_PROFILE_STORE){throw 'Team controls require the installed profile store.'}
        Import-Module (Join-Path $PSScriptRoot 'BeeForgeTeam.Core.psm1') -Force
        if($Action -eq 'FullAccessEnable'){$null=Set-BeeFullAccess -Enabled $true -Source 'BeeForge Next'}
        if($Action -eq 'FullAccessDisable'){$null=Set-BeeFullAccess -Enabled $false -Source 'BeeForge Next'}
        $s=Get-BeeFullAccessStatus
        $result=[ordered]@{Enabled=[bool]$s.Enabled;Configured=[bool]$s.Configured;Inconsistent=[bool]$s.Inconsistent;AgentCount=$s.AgentCount}
    }
    'SerenaProjects' {
        Import-Module (Join-Path $PSScriptRoot 'BeeForgeSerenaMemory.Core.psm1') -Force
        $result=[ordered]@{Projects=@(Get-BeeSerenaMemoryProjects|Select-Object Name,Path,Memories,Quality,Status)}
    }
}
ConvertTo-Json -InputObject $result -Depth 6 -Compress
