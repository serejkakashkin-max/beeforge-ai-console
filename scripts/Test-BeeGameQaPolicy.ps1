$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$config = [IO.File]::ReadAllText((Join-Path $root 'opencode\opencode.template.json'), [Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
$lead = [string]$config.agent.'team-lead'.prompt
$software = [string]$config.agent.'software-engineer'.prompt
$qa = [string]$config.agent.'qa-engineer'.prompt
$browserSkill = [IO.File]::ReadAllText((Join-Path $root 'opencode\skills\opencode-browser-qa\SKILL.md'), [Text.UTF8Encoding]::new($false))
$teamSkill = [IO.File]::ReadAllText((Join-Path $root 'opencode\skills\opencode-team-coordination\SKILL.md'), [Text.UTF8Encoding]::new($false))

foreach($text in @($lead,$software,$qa,$browserSkill,$teamSkill)){
    if($text -notmatch 'MANUAL_GAMEPLAY_REQUIRED'){throw 'Game QA manual acceptance marker is missing'}
}
if($lead -notmatch 'canvas' -or $lead -notmatch 'Quality Engineer'){
    throw 'Team Lead cannot distinguish game acceptance from normal web QA'
}
if($qa -notmatch 'не читай исходники' -or $qa -notmatch 'не запускай.*сервер'){
    throw 'Quality Engineer may rediscover game source or improvise a test server'
}
if($browserSkill -notmatch 'Do not play through' -or $browserSkill -notmatch 'developer handoff'){
    throw 'Browser QA skill still encourages autonomous gameplay or project rediscovery'
}

'GAME_QA_POLICY_TEST_OK'
