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