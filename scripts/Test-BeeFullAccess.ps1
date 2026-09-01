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
    foreach($scope in @($during.permission,$during.agent.alpha.permission,$during.agent.beta.permission)){
        $rules=@($scope.PSObject.Properties)
        if($rules.Count-ne1-or$rules[0].Name-ne'*'-or[string]$rules[0].Value-ne'allow'){throw "Full access retained a limiting permission rule: $($rules.Name -join ', ')"}
    }

    $during.marker='changed-during-full-access'
    $during.permission | Add-Member -NotePropertyName 'external_directory' -NotePropertyValue 'deny'
    $during.agent.alpha.permission | Add-Member -NotePropertyName 'bash' -NotePropertyValue 'ask'
    $module=Get-Module BeeForgeTeam.Core
    [void](& $module { param($candidate) Write-BeeTeamConfig $candidate 'self-test-save-during-full-access' } $during)
    $afterSave=[IO.File]::ReadAllText($openCodePath,[Text.UTF8Encoding]::new($false))|ConvertFrom-Json
    foreach($scope in @($afterSave.permission,$afterSave.agent.alpha.permission,$afterSave.agent.beta.permission)){
        $rules=@($scope.PSObject.Properties)
        if($rules.Count-ne1-or$rules[0].Name-ne'*'-or[string]$rules[0].Value-ne'allow'){throw "A later config save weakened full access: $($rules.Name -join ', ')"}
    }
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
