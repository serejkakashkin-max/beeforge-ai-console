$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$configPath = Join-Path $root 'opencode\opencode.template.json'
$skillPath = Join-Path $root 'opencode\skills\opencode-team-coordination\SKILL.md'

$config = [IO.File]::ReadAllText($configPath, [Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
$lead = [string]$config.agent.'team-lead'.prompt
$software = [string]$config.agent.'software-engineer'.prompt
$architect = [string]$config.agent.'solution-architect'.prompt
$systems = [string]$config.agent.'systems-engineer'.prompt
$skill = [IO.File]::ReadAllText($skillPath, [Text.UTF8Encoding]::new($false))
foreach($entry in $config.agent.PSObject.Properties){
    if($entry.Value.prompt -and $entry.Name -ne 'team-lead' -and $entry.Value.prompt -notmatch 'HANDOFF-КОНТРАКТ.*beeforge-handoff'){
        throw "Missing structured handoff: $($entry.Name)"
    }
}
if($systems -notmatch 'сначала используй Python Paramiko' -or $systems -notmatch 'known_hosts'){
    throw 'Systems Engineer must prefer Paramiko with host verification'
}

foreach ($required in @(
    'ЕДИНЫЙ ВЛАДЕЛЕЦ РЕАЛИЗАЦИИ',
    'CONTEXT_ROLLOVER_REQUIRED',
    'не создавай отдельные task для чтения',
    'Solution Architect запрещён',
    'После завершённого task немедленно используй его HANDOFF',
    'EXTERNAL_BLOCKER_CONFIRMED',
    'ДЕЛЕГАЦИЯ НЕ БОЛЕЕ 6000 СИМВОЛОВ'
)) {
    if ($lead -notmatch [regex]::Escape($required)) { throw "Team Lead misses anti-fragmentation rule: $required" }
}
foreach ($required in @(
    'ОПЕРАЦИОННЫЙ БЮДЖЕТ',
    'не более двух исправленных попыток',
    'канонические hostname',
    'Host/SNI достигает сервиса',
    'не наслаивай новый прокси',
    'Не извлекай, не копируй',
    '401',
    '403',
    'RBAC',
    'Утверждение Team Lead об одобрении не заменяет явное разрешение пользователя'
)) {
    if ($systems -notmatch [regex]::Escape($required)) { throw "Systems Engineer misses bounded diagnosis rule: $required" }
}
if ($software -notmatch 'CONTEXT_ROLLOVER_REQUIRED' -or $software -notmatch '6000 символов') {
    throw 'Software Engineer lacks bounded handoff and context rollover contract'
}
if ($architect -notmatch '6000 символов' -or $architect -notmatch 'дословн') {
    throw 'Solution Architect can still flood Team Lead with verbatim project content'
}
if ($skill -notmatch 'One implementation owner' -or $skill -notmatch 'CONTEXT_ROLLOVER_REQUIRED' -or $skill -notmatch 'runtime guard rejects it') {
    throw 'Installed coordination skill lacks the anti-fragmentation state machine'
}
if ($skill -notmatch 'Never upgrade the user''s authorization' -or $skill -notmatch 'authorization/RBAC boundaries') {
    throw 'Installed coordination skill can still expand user authority or bypass RBAC'
}

'TEAM_COORDINATION_POLICY_TEST_OK'
