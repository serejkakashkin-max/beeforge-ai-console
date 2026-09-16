Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'scripts\BeeLlamaManager.Core.psm1') -Force

$profile = Get-BeeNewProfileTemplate
$profile.modelPath = 'C:\fixture\tiel.gguf'
$profile.alias = 'Tiel-Test'
$profile.context = 190000
$profile.gpuLayers = '30'
$profile.batch = 1024
$profile.ubatch = 256
$profile.threads = 12
$profile.threadsBatch = 8
$profile.kvK = 'kvarn5'
$profile.kvV = 'kvarn3'
$profile.kvTailTokens = 2048
$profile.kvTailType = 'f16'
$profile.cacheReuse = 0
$profile.reasoningBudget = 16384
$profile.visionEnabled = $true
$profile.mmprojPath = 'C:\fixture\projector.gguf'
$profile.visionOffload = $false
$profile.mtpEnabled = $true
$profile.mtpNMax = 4
$profile.cpuMoeLayers = 18
$profile.tensorOverride = 'blk.(24-39).ffn_.*_exps.weight=CPU'
$profile.noMmap = $true
$profile.advancedArgs = @([pscustomobject]@{flag='--offline';value=''})

$actual = @(Get-BeeArguments $profile)
$expected = @(
    '-m','C:\fixture\tiel.gguf','--alias','Tiel-Test',
    '-ngl','30','-c','190000','-b','1024','-ub','256','-t','12','-tb','8',
    '-ctk','kvarn5','-ctv','kvarn3','--kv-tail-tokens','2048','--kv-tail-type','f16',
    '-fa','on','--fit','off','-np','1','--cache-reuse','0',
    '--reasoning','on','--reasoning-budget','16384','--reasoning-loop-guard','force-close',
    '--temp','1','--top-p','0.95','--top-k','20','--min-p','0',
    '--repeat-penalty','1','--host','127.0.0.1','--port','8080','--log-colors','off',
    '-mm','C:\fixture\projector.gguf','--no-mmproj-offload','--image-min-tokens','1024',
    '--reasoning-preserve','--spec-type','draft-mtp','--spec-draft-n-max','4',
    '--n-cpu-moe','18','-ot','blk.(24-39).ffn_.*_exps.weight=CPU','--no-mmap','--offline'
)
if ($actual.Count -ne $expected.Count) { throw "BeeLlama argv length changed: expected $($expected.Count), actual $($actual.Count)" }
for ($i=0; $i -lt $expected.Count; $i++) {
    if ($actual[$i] -cne $expected[$i]) { throw "BeeLlama argv changed at index $i; expected '$($expected[$i])', actual '$($actual[$i])'" }
}
'BEE_LLAMA_ARGV_SNAPSHOT_OK'
