param(
    [string]$ConfigPath = (Join-Path $env:USERPROFILE '.config\opencode\opencode.json')
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = [Text.UTF8Encoding]::new($false)
$utf8Bom = [Text.UTF8Encoding]::new($true)
$config = [IO.File]::ReadAllText($ConfigPath, $utf8NoBom) | ConvertFrom-Json

# Canonical prompts live in the distribution template. Never maintain a second copy here.
$templatePath=Join-Path (Split-Path $PSScriptRoot -Parent) 'opencode\opencode.template.json'
$template=[IO.File]::ReadAllText($templatePath,$utf8NoBom)|ConvertFrom-Json
foreach($entry in $template.agent.PSObject.Properties){
    if($config.agent.PSObject.Properties[$entry.Name] -and $entry.Value.prompt){
        $config.agent.($entry.Name).prompt=[string]$entry.Value.prompt
    }
}
$softwarePrompt=[string]$config.agent.'software-engineer'.prompt
$teamLeadPrompt=[string]$config.agent.'team-lead'.prompt
$architectPrompt=[string]$config.agent.'solution-architect'.prompt
$systemsPrompt=[string]$config.agent.'systems-engineer'.prompt

function Set-OrderedToolRules {
    param([Parameter(Mandatory=$true)]$Permission,[Parameter(Mandatory=$true)][System.Collections.Specialized.OrderedDictionary]$Rules)
    foreach($name in $Rules.Keys){[void]$Permission.PSObject.Properties.Remove([string]$name)}
    foreach($name in $Rules.Keys){$Permission|Add-Member NoteProperty ([string]$name) ([string]$Rules[$name])}
}

$softwareSkills = $config.agent.'software-engineer'.permission.skill
if (-not $softwareSkills.PSObject.Properties['opencode-serena-memory']) {
    $softwareSkills | Add-Member -MemberType NoteProperty -Name 'opencode-serena-memory' -Value 'allow'
} else {
    $softwareSkills.'opencode-serena-memory' = 'allow'
}

# OpenCode evaluates permission rules in insertion order and the last matching
# rule wins. When Full Access is active, preserve its sole wildcard rule.
$globalRules = @($config.permission.PSObject.Properties)
$fullAccessActive = $globalRules.Count -gt 0 -and $globalRules[0].Name -eq '*' -and [string]$globalRules[0].Value -eq 'allow'
$leadPermission = $config.agent.'team-lead'.permission
$leadSkills = $leadPermission.skill
$coordinationSkills = [ordered]@{'*'='deny'}
foreach($rule in @($leadSkills.PSObject.Properties)){
    if($rule.Name -ne '*' -and [string]$rule.Value -eq 'allow'){$coordinationSkills[$rule.Name]='allow'}
}
$leadTask = $leadPermission.task
$config.agent.'team-lead'.permission = [pscustomobject][ordered]@{
    '*' = 'deny'
    skill = [pscustomobject]$coordinationSkills
    task = $leadTask
    todowrite = 'allow'
}
if (-not $fullAccessActive) {
Set-OrderedToolRules -Permission $config.agent.'software-engineer'.permission -Rules ([ordered]@{
    'serena*' = 'allow'
    'serena_activate_project' = 'allow'
    'serena_remove_project' = 'deny'
})
Set-OrderedToolRules -Permission $config.agent.'solution-architect'.permission -Rules ([ordered]@{
    'serena*' = 'allow'
    'serena_create_text_file' = 'deny'
    'serena_replace_content' = 'deny'
    'serena_replace_in_files' = 'deny'
    'serena_replace_symbol_body' = 'deny'
    'serena_insert_after_symbol' = 'deny'
    'serena_insert_before_symbol' = 'deny'
    'serena_rename_symbol' = 'deny'
    'serena_safe_delete_symbol' = 'deny'
    'serena_delete_lines' = 'deny'
    'serena_replace_lines' = 'deny'
    'serena_insert_at_line' = 'deny'
    'serena_execute_shell_command' = 'deny'
    'serena_write_memory' = 'allow'
    'serena_delete_memory' = 'ask'
    'serena_edit_memory' = 'allow'
    'serena_rename_memory' = 'allow'
    'serena_activate_project' = 'allow'
    'serena_remove_project' = 'deny'
})
foreach($agentId in 'qa-engineer','devops-engineer','platform-engineer'){
    Set-OrderedToolRules -Permission $config.agent.$agentId.permission -Rules ([ordered]@{
        'serena_initial_instructions' = 'allow'
        'serena_get_current_config' = 'allow'
        'serena_activate_project' = 'allow'
        'serena_list_memories' = 'allow'
        'serena_read_memory' = 'allow'
        'serena_write_memory' = 'allow'
        'serena_edit_memory' = 'allow'
        'serena_rename_memory' = 'deny'
        'serena_delete_memory' = 'deny'
        'serena_remove_project' = 'deny'
    })
}
}

if ($config.mcp.serena) { $config.mcp.serena.timeout = 240000 }

$temp = "$ConfigPath.tmp"
$json = $config | ConvertTo-Json -Depth 100
[IO.File]::WriteAllText($temp, $json + [Environment]::NewLine, $utf8Bom)
[void]([IO.File]::ReadAllText($temp, $utf8NoBom) | ConvertFrom-Json)
Move-Item -LiteralPath $temp -Destination $ConfigPath -Force

# The permission policy above intentionally remains restricted in normal mode.
# If Full Access is active, reconcile newly selected skills/MCPs into its saved
# ordinary baseline and repair the unrestricted overlay atomically.
if($fullAccessActive){
    $teamModulePath=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\BeeForgeTeam.Core.psm1'
    if(Test-Path -LiteralPath $teamModulePath){
        Import-Module $teamModulePath -Force
        $teamPaths=Get-BeeTeamPaths
        if([IO.Path]::GetFullPath([string]$teamPaths.Config)-eq[IO.Path]::GetFullPath($ConfigPath)){
            [void](Set-BeeFullAccess -Enabled $true -Source 'semantic-policy-reconcile')
        }
    }
}

[pscustomobject]@{
    updated = $true
    config = $ConfigPath
    softwarePromptChars = $config.agent.'software-engineer'.prompt.Length
    teamLeadPromptChars = $config.agent.'team-lead'.prompt.Length
    architectPromptChars = $config.agent.'solution-architect'.prompt.Length
    systemsPromptChars = $config.agent.'systems-engineer'.prompt.Length
    serenaTimeoutMs = $config.mcp.serena.timeout
} | ConvertTo-Json -Compress
