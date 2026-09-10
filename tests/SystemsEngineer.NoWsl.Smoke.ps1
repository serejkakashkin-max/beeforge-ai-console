Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$agentsPath = Join-Path $root 'opencode\AGENTS.md'
$templatePath = Join-Path $root 'opencode\opencode.template.json'
$skillPath = Join-Path $root 'opencode\skills\opencode-safe-operations\SKILL.md'
$agents = [IO.File]::ReadAllText($agentsPath)
$templateText = [IO.File]::ReadAllText($templatePath)
$skill = [IO.File]::ReadAllText($skillPath)
$template = $templateText | ConvertFrom-Json
$systemsPrompt = [string]$template.agent.'systems-engineer'.prompt
$sshTemplate = [string]$template.command.ssh.template

if ($agents -notmatch 'WSL is forbidden for agent operations') { throw 'Global agent policy does not forbid WSL' }
if ($agents -notmatch 'Paramiko') { throw 'Global SSH policy does not prefer native Paramiko for authorized password auth' }
if ($agents -notmatch 'HANDOFF\.md') { throw 'Global policy does not distinguish virtual HANDOFF from HANDOFF.md' }
if ($systemsPrompt -match 'Ты Systems Engineer для Windows, WSL и SSH') { throw 'Systems Engineer still advertises WSL as an operating domain' }
if ($systemsPrompt -notmatch 'WSL для агентных операций ЗАПРЕЩЁН') { throw 'Systems Engineer prompt does not explicitly forbid WSL' }
if ($systemsPrompt -notmatch 'Paramiko') { throw 'Systems Engineer prompt does not route authorized password auth through native Paramiko' }
if ($systemsPrompt -notmatch 'BEEFORGE_PREVIOUS_HANDOFF_DATA' -or $systemsPrompt -notmatch 'HANDOFF\.md') { throw 'Systems Engineer prompt does not distinguish injected HANDOFF data from a physical file' }
if ($sshTemplate -notmatch 'без WSL' -or $sshTemplate -notmatch 'Paramiko') { throw '/ssh command policy is not native-Windows only' }
if ($skill -notmatch 'WSL is forbidden for agent operations' -or $skill -notmatch 'Paramiko') { throw 'Safe-operations skill does not enforce native-Windows SSH' }
if ($templateText -match 'Windows/WSL/SSH направляй systems-engineer') { throw 'Team Lead still routes WSL as a supported domain' }
Write-Host 'Systems Engineer no-WSL policy smoke test passed.'
