[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$utf8Bom = [Text.UTF8Encoding]::new($true)

$core = Join-Path $root 'scripts\BeeLlamaManager.Core.psm1'
$ui = Join-Path $root 'ui\BeeLlama-Manager.ps1'
if (-not ([IO.File]::ReadAllText($core).Contains('cpuMoeLayers = 0'))) { throw 'Core MoE patch was not applied before completion step.' }
if (-not ([IO.File]::ReadAllText($ui).Contains('Name="MoeGroup"'))) { throw 'UI MoE patch was not applied before completion step.' }

# Update example profiles structurally so line endings/format do not matter.
$template = Join-Path $root 'config\templates\profiles.example.json'
$data = [IO.File]::ReadAllText($template,[Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
foreach ($profile in @($data.profiles)) {
    foreach ($pair in @(
        @('cpuMoeLayers',0),
        @('cpuMoeAll',$false),
        @('moeLayerCount',0),
        @('moeExpertWeightFraction',0.0),
        @('modelLayerCount',0)
    )) {
        if ($profile.PSObject.Properties[$pair[0]]) { $profile.($pair[0]) = $pair[1] }
        else { $profile | Add-Member -NotePropertyName $pair[0] -NotePropertyValue $pair[1] }
    }
}
[IO.File]::WriteAllText($template,($data | ConvertTo-Json -Depth 20),$utf8Bom)

# Add user-facing MoE documentation once.
$readme = Join-Path $root 'README.md'
$text = [IO.File]::ReadAllText($readme,[Text.UTF8Encoding]::new($false))
if ($text -notmatch '## MoE и перенос routed experts на CPU') {
    $section = @'
## MoE и перенос routed experts на CPU

Для MoE-моделей BeeForge имеет отдельный блок **MoE / CPU offload** на вкладке
**Производительность**. Поле **CPU MoE layers** напрямую управляет
`--n-cpu-moe N`; значение `0` отключает принудительный перенос. Флажок
**Все MoE experts на CPU** соответствует `--cpu-moe` и взаимоисключаем с числом
CPU MoE layers.

Поля **MoE layers**, **Expert weights %** и **Model layers** используются только
для оценки ресурсов и динамического списка GPU layers. Для известных семейств
(Ornith/Tiel/KAT/Qwen3.6-35B-A3B, Gemma4-26B-A4B, Qwen3.8-27B) интерфейс подставляет
разумный пресет; значения можно скорректировать вручную. Старые профили, где
`--n-cpu-moe` или `--cpu-moe` были записаны во вкладке Advanced, автоматически
мигрируют в нативные поля.

Для MoE/hybrid-attention вкладка **Ресурсы** учитывает оценочную долю routed expert
weights, переносимую в RAM. Оценка KV остаётся консервативной до первого реального
запуска, потому что разные hybrid/linear-attention архитектуры имеют разную стоимость
контекста. После запуска ориентируйтесь на фактические VRAM/RAM и встроенный benchmark.

Пример стартовой конфигурации Ornith-1.5-35B-A3B на 16 GiB GPU:

```text
GPU layers:       all
CPU MoE layers:   16
MoE layers:       40
Expert weights:   93%
Model layers:     40
Flash Attention:  on
MTP:              off (для первого baseline)
```

'@
    $marker = '## Встроенный benchmark'
    $idx = $text.IndexOf($marker,[StringComparison]::Ordinal)
    if ($idx -lt 0) { throw 'README benchmark section anchor not found.' }
    $text = $text.Substring(0,$idx) + $section + $text.Substring($idx)
    [IO.File]::WriteAllText($readme,$text,$utf8Bom)
}

# Durable smoke test.
$testsDir = Join-Path $root 'tests'
if (-not (Test-Path -LiteralPath $testsDir)) { New-Item -ItemType Directory -Path $testsDir -Force | Out-Null }
$smoke = @'
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'scripts\BeeLlamaManager.Core.psm1') -Force

$p = Get-BeeNewProfileTemplate
$p.cpuMoeLayers = 16
$p.cpuMoeAll = $false
$args1 = @(Get-BeeArguments $p)
$i = [Array]::IndexOf($args1,'--n-cpu-moe')
if ($i -lt 0 -or $i + 1 -ge $args1.Count -or $args1[$i+1] -ne '16') { throw '--n-cpu-moe 16 was not emitted' }

$p.cpuMoeLayers = 0
$p.cpuMoeAll = $true
$args2 = @(Get-BeeArguments $p)
if ($args2 -notcontains '--cpu-moe') { throw '--cpu-moe was not emitted' }
if ($args2 -contains '--n-cpu-moe') { throw 'numeric CPU MoE flag must not be emitted with cpuMoeAll' }
Write-Host 'MoE profile smoke test passed.'
'@
[IO.File]::WriteAllText((Join-Path $testsDir 'MoEProfile.Smoke.ps1'),$smoke,$utf8Bom)

# Durable CI for future edits.
$workflowDir = Join-Path $root '.github\workflows'
if (-not (Test-Path -LiteralPath $workflowDir)) { New-Item -ItemType Directory -Path $workflowDir -Force | Out-Null }
$ci = @'
name: PowerShell smoke
on:
  push:
    branches: [ main ]
  pull_request:
permissions:
  contents: read
jobs:
  smoke:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - name: Parse PowerShell
        shell: pwsh
        run: |
          $files = @('scripts/BeeLlamaManager.Core.psm1','ui/BeeLlama-Manager.ps1','tests/MoEProfile.Smoke.ps1')
          foreach ($file in $files) {
            $tokens = $null; $errors = $null
            [void][Management.Automation.Language.Parser]::ParseFile((Resolve-Path $file),[ref]$tokens,[ref]$errors)
            if ($errors.Count) { $errors | Format-List | Out-String | Write-Error; exit 1 }
          }
      - name: MoE profile smoke
        shell: pwsh
        run: pwsh -NoProfile -File tests/MoEProfile.Smoke.ps1
'@
[IO.File]::WriteAllText((Join-Path $workflowDir 'powershell-smoke.yml'),$ci,$utf8Bom)

Write-Host 'MoE upgrade completion step succeeded.'
