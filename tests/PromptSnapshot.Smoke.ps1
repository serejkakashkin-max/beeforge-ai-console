Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$baseline = [IO.File]::ReadAllText((Join-Path $root 'docs\merge\baseline.json'), [Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
$config = [IO.File]::ReadAllText((Join-Path $root 'opencode\opencode.template.json'), [Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
$expectedIds = @($baseline.promptSha256Utf8.PSObject.Properties.Name | Sort-Object)
$actualIds = @($config.agent.PSObject.Properties.Name | Sort-Object)
if (($expectedIds -join ',') -cne ($actualIds -join ',')) { throw 'Agent set changed from the BeeForge main baseline' }
$sha = [Security.Cryptography.SHA256]::Create()
try {
    foreach ($agent in $config.agent.PSObject.Properties) {
        $prompt = if ($agent.Value.PSObject.Properties['prompt']) { [string]$agent.Value.prompt } else { '' }
        $bytes = [Text.Encoding]::UTF8.GetBytes($prompt)
        $actual = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
        $expected = [string]$baseline.promptSha256Utf8.PSObject.Properties[$agent.Name].Value
        if ($actual -cne $expected) { throw "Agent prompt changed: $($agent.Name)" }
    }
} finally {
    $sha.Dispose()
}
'PROMPT_SNAPSHOT_OK'
