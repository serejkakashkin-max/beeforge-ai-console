[CmdletBinding()]
param()

$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$temp=Join-Path ([IO.Path]::GetTempPath()) ('beeforge-serena-memory-'+[guid]::NewGuid().ToString('N'))
$project=Join-Path $temp 'project';$fake=Join-Path $temp 'fake-serena.ps1';$ensure=Join-Path $temp 'ensure.ps1'
try {
    New-Item -ItemType Directory -Path $project -Force|Out-Null
    @'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
$project=$Arguments[-1]
if($Arguments -contains 'initialize'){
  $dir=Join-Path $project '.serena\memories';New-Item -ItemType Directory -Path $dir -Force|Out-Null
  Set-Content -LiteralPath (Join-Path $dir 'memory_maintenance.md') -Value '# maintenance' -Encoding UTF8
}
exit 0
'@|Set-Content -LiteralPath $fake -Encoding UTF8
    @'
param([string]$ProjectPath)
$dir=Join-Path $ProjectPath '.serena';New-Item -ItemType Directory -Path $dir -Force|Out-Null
Set-Content -LiteralPath (Join-Path $dir 'project.yml') -Value "project_name: test`nread_only: true" -Encoding UTF8
'@|Set-Content -LiteralPath $ensure -Encoding UTF8
    $env:BEEFORGE_SERENA_MEMORY_POLICY_PATH=Join-Path $temp 'policy.json'
    $env:BEEFORGE_SERENA_CONFIG_PATH=Join-Path $temp 'serena.yml'
    $env:BEEFORGE_TELEGRAM_CONFIG_PATH=Join-Path $temp 'telegram.json'
    $env:BEEFORGE_OPENCODE_GLOBAL_DATA=Join-Path $temp 'opencode.dat'
    $env:BEEFORGE_SERENA_EXE=(Get-Command pwsh).Source
    $env:BEEFORGE_SERENA_ENSURE_SCRIPT=$ensure
    Import-Module (Join-Path $root 'scripts\BeeForgeSerenaMemory.Core.psm1') -Force
    # Wrap pwsh so the module invocation receives the fake script as its first argument.
    $paths=Get-BeeSerenaMemoryPaths;$paths.SerenaExe=$fake
    $env:BEEFORGE_SERENA_EXE=$fake
    $enabled=Enable-BeeSerenaProjectMemory -ProjectPath $project
    if(-not$enabled.Managed-or$enabled.ReadOnly-ne$false-or$enabled.Status-ne'NEEDS_ONBOARDING'){throw 'Managed initialization failed'}
    foreach($name in @('core','tech_stack','suggested_commands','conventions','task_completion')){Set-Content -LiteralPath (Join-Path $enabled.MemoryDirectory "$name.md") -Value "# $name" -Encoding UTF8}
    if((Get-BeeSerenaMemoryStatus $project).Status-ne'READY'){throw 'Required memory readiness failed'}
    $status=Get-BeeSerenaMemoryStatus $project
    if(-not$status.Managed-or$status.ReadOnly-ne$false-or$status.Status-ne'READY'){throw 'Unified persistent mode failed'}
    'SERENA_MEMORY_TEST_OK'
} finally {
    Remove-Item Env:BEEFORGE_SERENA_MEMORY_POLICY_PATH,Env:BEEFORGE_SERENA_CONFIG_PATH,Env:BEEFORGE_TELEGRAM_CONFIG_PATH,Env:BEEFORGE_OPENCODE_GLOBAL_DATA,Env:BEEFORGE_SERENA_EXE,Env:BEEFORGE_SERENA_ENSURE_SCRIPT -ErrorAction SilentlyContinue
    if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}
}
