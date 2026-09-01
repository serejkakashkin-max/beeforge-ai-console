$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$configPath = Join-Path $root 'opencode\opencode.template.json'
$skillPath = Join-Path $root 'opencode\skills\opencode-serena-memory\SKILL.md'

$config = [IO.File]::ReadAllText($configPath, [Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
$teamLead = $config.agent.'team-lead'
$software = $config.agent.'software-engineer'
$architect = $config.agent.'solution-architect'
$qa = $config.agent.'qa-engineer'
$devops = $config.agent.'devops-engineer'
$platform = $config.agent.'platform-engineer'
$skill = [IO.File]::ReadAllText($skillPath, [Text.UTF8Encoding]::new($false))

if ($software.permission.skill.'opencode-serena-memory' -ne 'allow') {
    throw 'Software Engineer has no Serena memory skill'
}
if ($software.permission.'serena*' -ne 'allow') {
    throw 'Software Engineer cannot use Serena memory tools'
}
if ($teamLead.prompt -notmatch 'Serena memory' -or $teamLead.prompt -notmatch 'Solution Architect' -or $teamLead.prompt -notmatch 'Software Engineer') {
    throw 'Team Lead still lacks the direct implementation routing rule'
}
if ($software.prompt -notmatch 'memory_maintenance' -or $software.prompt -notmatch '5/5' -or $software.prompt -notmatch 'HANDOFF') {
    throw 'Software Engineer lacks lazy memory maintenance rules'
}
if ($architect.prompt -notmatch 'onboarding' -or $architect.prompt -notmatch 'memory_maintenance') {
    throw 'Solution Architect onboarding scope is not explicit'
}
if ($architect.permission.serena_write_memory -ne 'allow' -or $architect.permission.serena_delete_memory -ne 'ask') {
    throw 'Solution Architect memory permissions are unsafe or incomplete'
}
if ($skill -notmatch 'Missing or incomplete memories never block the requested task') {
    throw 'Installed skill source lacks lazy maintenance contract'
}
if ($skill -notmatch 'Last verified: YYYY-MM-DD' -or $skill -notmatch 'Memory: unchanged') {
    throw 'Memory verification and handoff contract is missing'
}
foreach ($agent in @($qa,$devops,$platform)) {
    if ($agent.permission.skill.'opencode-serena-memory' -ne 'allow') { throw 'Domain agent has no Serena memory skill' }
    if ($agent.permission.serena_write_memory -ne 'allow' -or $agent.permission.serena_delete_memory -ne 'deny') { throw 'Domain memory permissions are unsafe or incomplete' }
    if ($agent.prompt -notmatch 'Memory: unchanged') { throw 'Domain agent lacks memory handoff reporting' }
}

'SERENA_LAZY_MEMORY_TEST_OK'
