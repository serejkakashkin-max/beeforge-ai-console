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
        permission=[pscustomobject]@{read='allow';bash='ask';task='deny'}
        mcp=[pscustomobject]@{serena=[pscustomobject]@{enabled=$true};github=[pscustomobject]@{enabled=$true}}
        agent=[pscustomobject]@{
            alpha=[pscustomobject]@{permission=[pscustomobject]@{read='allow';edit='ask';skill=[pscustomobject]@{'*'='deny';'diagnosing-bugs'='allow'};'serena*'='allow';'github*'='deny';task=[pscustomobject]@{'*'='deny';beta='allow'}}}
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
        if($rules[0].Name-ne'*'-or[string]$rules[0].Value-ne'allow'){throw "Full access wildcard is missing: $($rules.Name -join ', ')"}
    }
    if([string]$during.agent.alpha.permission.skill.'*'-ne'allow'-or[string]$during.agent.alpha.permission.skill.'diagnosing-bugs'-ne'allow'-or[string]$during.agent.alpha.permission.'serena*'-ne'allow'-or$during.agent.alpha.permission.PSObject.Properties['github*']){throw 'Selected skill/MCP metadata was not preserved while enabling full access'}
    if([string]$during.permission.task-ne'deny'-or[string]$during.agent.alpha.permission.task.'*'-ne'deny'-or[string]$during.agent.alpha.permission.task.beta-ne'allow'-or$during.agent.alpha.permission.task.PSObject.Properties['explore']){throw 'Team routing was not preserved while enabling full access'}

    $during.marker='changed-during-full-access'
    $during.permission | Add-Member -NotePropertyName 'external_directory' -NotePropertyValue 'deny'
    $during.agent.alpha.permission | Add-Member -NotePropertyName 'bash' -NotePropertyValue 'ask'
    $during.agent.alpha.permission.task | Add-Member -NotePropertyName 'explore' -NotePropertyValue 'allow'
    $module=Get-Module BeeForgeTeam.Core
    [void](& $module { param($candidate) Write-BeeTeamConfig $candidate 'self-test-save-during-full-access' } $during)
    $afterSave=[IO.File]::ReadAllText($openCodePath,[Text.UTF8Encoding]::new($false))|ConvertFrom-Json
    foreach($scope in @($afterSave.permission,$afterSave.agent.alpha.permission,$afterSave.agent.beta.permission)){
        $rules=@($scope.PSObject.Properties)
        if($rules[0].Name-ne'*'-or[string]$rules[0].Value-ne'allow'-or@($rules|Where-Object{[string]$_.Value-in@('ask','deny')-and$_.Name-ne'task'}).Count){throw "A later config save weakened full access: $($rules.Name -join ', ')"}
    }
    if($afterSave.agent.alpha.permission.task.PSObject.Properties['explore']){throw 'A later config save expanded Team Lead routing to an unconfigured agent'}
    $afterSave.agent.alpha.permission.skill.PSObject.Properties.Remove('diagnosing-bugs')
    $afterSave.agent.alpha.permission.skill|Add-Member -NotePropertyName 'find-docs' -NotePropertyValue 'allow'
    $afterSave.agent.alpha.permission.PSObject.Properties.Remove('serena*')
    $afterSave.agent.alpha.permission|Add-Member -NotePropertyName 'github*' -NotePropertyValue 'allow'
    [void](& $module { param($candidate) Write-BeeTeamConfig $candidate 'save-agent' } $afterSave)
    $afterAssignmentSave=[IO.File]::ReadAllText($openCodePath,[Text.UTF8Encoding]::new($false))|ConvertFrom-Json
    if($afterAssignmentSave.agent.alpha.permission.skill.PSObject.Properties['diagnosing-bugs']-or[string]$afterAssignmentSave.agent.alpha.permission.skill.'find-docs'-ne'allow'-or$afterAssignmentSave.agent.alpha.permission.PSObject.Properties['serena*']-or[string]$afterAssignmentSave.agent.alpha.permission.'github*'-ne'allow'){throw 'Skill/MCP assignment changes were not retained during full access'}
    $tampered=[IO.File]::ReadAllText($openCodePath,[Text.UTF8Encoding]::new($false))|ConvertFrom-Json
    $tampered.agent.alpha.permission.task|Add-Member -NotePropertyName 'explore' -NotePropertyValue 'allow'
    [IO.File]::WriteAllText($openCodePath,($tampered|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
    $tamperedStatus=Get-BeeFullAccessStatus
    if(-not$tamperedStatus.Inconsistent-or$tamperedStatus.Enabled){throw 'Expanded Team Lead routing was not detected as an inconsistent full-access state'}
    $repaired=Set-BeeFullAccess -Enabled $true -Source 'self-test-repair-routing'
    $repairedConfig=[IO.File]::ReadAllText($openCodePath,[Text.UTF8Encoding]::new($false))|ConvertFrom-Json
    if(-not$repaired.Enabled-or$repairedConfig.agent.alpha.permission.task.PSObject.Properties['explore']){throw 'Full access did not repair expanded Team Lead routing'}
    $disabled=Set-BeeFullAccess -Enabled $false -Source 'self-test'
    if($disabled.Enabled-or$disabled.Inconsistent){throw 'Full access did not return to a consistent disabled state'}
    $after=[IO.File]::ReadAllText($openCodePath,[Text.UTF8Encoding]::new($false))|ConvertFrom-Json
    if($after.marker-ne'changed-during-full-access'){throw 'A non-permission config change was lost during restore'}
    if($after.permission.PSObject.Properties['*']-or$after.agent.alpha.permission.PSObject.Properties['*']-or$after.agent.beta.PSObject.Properties['permission']){throw 'Original permission shape was not restored'}
    if([string]$after.permission.bash-ne'ask'-or[string]$after.permission.task-ne'deny'-or[string]$after.agent.alpha.permission.edit-ne'ask'-or[string]$after.agent.alpha.permission.task.beta-ne'allow'){throw 'Original permission values or routing were not restored'}
    if($after.agent.alpha.permission.skill.PSObject.Properties['diagnosing-bugs']-or[string]$after.agent.alpha.permission.skill.'find-docs'-ne'allow'-or$after.agent.alpha.permission.PSObject.Properties['serena*']-or[string]$after.agent.alpha.permission.'github*'-ne'allow'){throw 'Updated skill/MCP assignments were not restored after disabling full access'}

    [pscustomobject]@{passed=$true;enabledAgents=$enabled.AgentCount;nonPermissionChangePreserved=$true;permissionsRestored=$true}|ConvertTo-Json -Compress
} finally {
    Remove-Module BeeForgeTeam.Core -Force -ErrorAction SilentlyContinue
    if(Test-Path -LiteralPath $testRoot){Remove-Item -LiteralPath $testRoot -Recurse -Force}
}
