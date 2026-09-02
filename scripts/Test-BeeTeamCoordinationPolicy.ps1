$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$configPath = Join-Path $root 'opencode\opencode.template.json'
$skillPath = Join-Path $root 'opencode\skills\opencode-team-coordination\SKILL.md'

$config = [IO.File]::ReadAllText($configPath, [Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
$lead = [string]$config.agent.'team-lead'.prompt
$software = [string]$config.agent.'software-engineer'.prompt
$architect = [string]$config.agent.'solution-architect'.prompt
$skill = [IO.File]::ReadAllText($skillPath, [Text.UTF8Encoding]::new($false))

foreach ($required in @(
    'ЕДИНЫЙ ВЛАДЕЛЕЦ РЕАЛИЗАЦИИ',
    'CONTEXT_ROLLOVER_REQUIRED',
    'не создавай отдельные task для чтения',
    'Solution Architect запрещён'
)) {
    if ($lead -notmatch [regex]::Escape($required)) { throw "Team Lead misses anti-fragmentation rule: $required" }
}
if ($software -notmatch 'CONTEXT_ROLLOVER_REQUIRED' -or $software -notmatch '6000 символов') {
    throw 'Software Engineer lacks bounded handoff and context rollover contract'
}
if ($architect -notmatch '6000 символов' -or $architect -notmatch 'дословн') {
    throw 'Solution Architect can still flood Team Lead with verbatim project content'
}
if ($skill -notmatch 'One implementation owner' -or $skill -notmatch 'CONTEXT_ROLLOVER_REQUIRED') {
    throw 'Installed coordination skill lacks the anti-fragmentation state machine'
}

'TEAM_COORDINATION_POLICY_TEST_OK'
