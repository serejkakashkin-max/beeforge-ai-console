Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'scripts\BeeLlamaManager.Core.psm1') -Force

$p = Get-BeeNewProfileTemplate
if ([int]$p.openCodeOutput -ne 32768) { throw 'New profile output default must be 32768' }

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

$p.cpuMoeAll = $false
$p.tensorOverride = 'blk.(24-39).ffn_.*_exps.weight=CPU'
$p.noMmap = $true
$args3 = @(Get-BeeArguments $p)
$oi = [Array]::IndexOf($args3,'-ot')
if ($oi -lt 0 -or $args3[$oi+1] -ne $p.tensorOverride) { throw 'tensor override was not emitted' }
if ($args3 -notcontains '--no-mmap') { throw '--no-mmap was not emitted' }

$f1 = Get-BeeProfileRuntimeFingerprint $p
$p.batch = 1024
$f2 = Get-BeeProfileRuntimeFingerprint $p
if ($f1 -eq $f2) { throw 'runtime fingerprint did not change after batch change' }

$ok = Test-BeeVisionProjectorCompatibility 'C:\Models\Qwen3.8-27B\model.gguf' 'C:\Models\Qwen3.8-27B\mmproj-F16.gguf'
if (-not $ok.Compatible -or -not $ok.Certain) { throw 'same-folder projector should be accepted' }
$bad = Test-BeeVisionProjectorCompatibility 'C:\Models\Ornith-1.5\model.gguf' 'C:\Models\Qwen3.8-27B\mmproj-Qwen3.8-BF16.gguf'
if ($bad.Compatible -or -not $bad.Certain) { throw 'obvious cross-family projector mismatch should be rejected' }

$uiScript = [IO.File]::ReadAllText((Join-Path $root 'ui\BeeLlama-Manager.ps1'), [Text.UTF8Encoding]::new($true))
$expectedKvItems = "@('f16','bf16','q8_0','q4_0','iq4_nl','kvarn8','kvarn6','kvarn5','kvarn4','kvarn3','kvarn2')"
if (-not $uiScript.Contains($expectedKvItems)) { throw 'UI must expose every BeeLlama KVarN width: 8, 6, 5, 4, 3, 2' }
foreach ($entry in @("'kvarn8' { return 1.8611 }","'kvarn6' { return 1.4167 }","'kvarn5' { return 1.1944 }","'kvarn4' { return 0.9722 }","'kvarn3' { return 0.75 }","'kvarn2' { return 0.5278 }")) {
    if (-not $uiScript.Contains($entry)) { throw "KV resource estimator is missing: $entry" }
}

Write-Host 'Runtime profile smoke test passed.'
