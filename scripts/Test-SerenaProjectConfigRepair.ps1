[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$ensure = Join-Path $root 'tools\serena\v1.7.0\ensure-project-language.ps1'
$python = Join-Path $root 'tools\serena\v1.7.0\.venv\Scripts\python.exe'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('beeforge-serena-project-yaml-' + [guid]::NewGuid().ToString('N'))
$project = Join-Path $temp 'project'

try {
    New-Item -ItemType Directory -Path (Join-Path $project '.serena') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $project 'index.ts') -Value 'export const value = 1;' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $project 'index.html') -Value '<script>function startGame(){}</script>' -Encoding UTF8
    @'
project_name: "project"
language_servers:
- typescript
read_only: false
initial_prompt: "BeeForge project: valid scalar."
  stale continuation from an interrupted earlier update
ls_workspace_folders:
- "."
'@ | Set-Content -LiteralPath (Join-Path $project '.serena\project.yml') -Encoding UTF8

    & $ensure -ProjectPath $project | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Preflight failed: $LASTEXITCODE" }

    $config = Join-Path $project '.serena\project.yml'
    $raw = [IO.File]::ReadAllText($config, [Text.UTF8Encoding]::new($false))
    if ($raw -match 'stale continuation') { throw 'Malformed initial_prompt continuation was not removed' }
    if ($raw -notmatch '(?m)^initial_prompt: "BeeForge project:') { throw 'Initial prompt was not normalized' }
    if ($raw -notmatch '(?m)^- html\s*$') { throw 'HTML language server was not enabled' }
    & $python -c "from ruamel.yaml import YAML; YAML(typ='safe').load(open(r'$config', encoding='utf-8-sig'))" 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'Repaired project.yml is not valid YAML' }
    'SERENA_PROJECT_CONFIG_REPAIR_TEST_OK'
} finally {
    $globalConfig = Join-Path $env:USERPROFILE '.serena\serena_config.yml'
    if (Test-Path -LiteralPath $globalConfig) {
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.AddRange([IO.File]::ReadAllLines($globalConfig, [Text.UTF8Encoding]::new($false)))
        $testPath = $project.TrimEnd('\')
        $changed = $false
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            if ($lines[$i] -match '^\s*-\s*(.+?)\s*$' -and $matches[1].Trim('"','''').TrimEnd('\') -eq $testPath) {
                $lines.RemoveAt($i)
                $changed = $true
            }
        }
        if ($changed) { [IO.File]::WriteAllLines($globalConfig, $lines, [Text.UTF8Encoding]::new($false)) }
    }
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
