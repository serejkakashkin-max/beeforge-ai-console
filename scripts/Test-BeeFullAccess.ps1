$ErrorActionPreference = 'Stop'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('beeforge-full-access-' + [guid]::NewGuid().ToString('N'))
$scripts = Join-Path $testRoot 'scripts'
$configDir = Join-Path $testRoot 'config'
$openCodePath = Join-Path $testRoot 'opencode.json'

try {
    New-Item -ItemType Directory -Path $scripts,$configDir -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'BeeForgeTeam.Core.psm1') -Destination (Join-Path $scripts 'BeeForgeTeam.Core.psm1')
    $profiles = [pscustomobject]@{openCodeConfigPath=$openCodePath}
    $original = [pscustomobject]@{
        permission=[pscustomobject]@{read='allow';bash='ask'}
        agent=[pscustomobject]@{
            alpha=[pscustomobject]@{permission=[pscustomobject]@{read='allow';edit='ask'}}
            beta=[pscustomobject]@{description='no permission initially'}
        }
        marker='before'
    }
    [IO.File]::WriteAllText((Join-Path $configDir 'profiles.json'),($profiles|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($openCodePath,($original|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
    Import-Module (Join-Path $scripts 'BeeForgeTeam.Core.psm1') -Force

    $enabled=Set-BeeFullAccess -Enabled $true -Source 'self-test'
    if(-not$enabled.Enabled){throw 'Full access did not become enabled'}
    $during=[IO.File]::ReadAllText($openCodePath,[Text.UTF8Encoding]::new($false))|ConvertFrom-Json
    if([string]$during.permission.'*'-ne'allow'-or[string]$during.agent.alpha.permission.'*'-ne'allow'-or[string]$during.agent.beta.permission.'*'-ne'allow'){throw 'Wildcard allow was not applied to all permission scopes'}

    $during.marker='changed-during-full-access'
    [IO.File]::WriteAllText($openCodePath,($during|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
    $disabled=Set-BeeFullAccess -Enabled $false -Source 'self-test'
    if($disabled.Enabled-or$disabled.Inconsistent){throw 'Full access did not return to a consistent disabled state'}
    $after=[IO.File]::ReadAllText($openCodePath,[Text.UTF8Encoding]::new($false))|ConvertFrom-Json
    if($after.marker-ne'changed-during-full-access'){throw 'A non-permission config change was lost during restore'}
    if($after.permission.PSObject.Properties['*']-or$after.agent.alpha.permission.PSObject.Properties['*']-or$after.agent.beta.PSObject.Properties['permission']){throw 'Original permission shape was not restored'}
    if([string]$after.permission.bash-ne'ask'-or[string]$after.agent.alpha.permission.edit-ne'ask'){throw 'Original permission values were not restored'}

    [pscustomobject]@{passed=$true;enabledAgents=$enabled.AgentCount;nonPermissionChangePreserved=$true;permissionsRestored=$true}|ConvertTo-Json -Compress
} finally {
    Remove-Module BeeForgeTeam.Core -Force -ErrorAction SilentlyContinue
    if(Test-Path -LiteralPath $testRoot){Remove-Item -LiteralPath $testRoot -Recurse -Force}
}
