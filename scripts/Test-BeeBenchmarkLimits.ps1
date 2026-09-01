[CmdletBinding()]
param()

$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'BeeLlamaManager.Core.psm1') -Force

$resolved=Resolve-BeeBenchmarkRequest -Context 162000 -PromptTokens 32768 -OutputTokens 32768 -TimeoutSec 900
if($resolved.OutputTokens-ne4096){throw "Expected output clamp to 4096, got $($resolved.OutputTokens)"}
if($resolved.PromptTokens-ne32768){throw "Unexpected input adjustment: $($resolved.PromptTokens)"}
if($resolved.Adjustments-notmatch'32768.*4096'){throw 'Output adjustment message is missing'}

$minimum=Resolve-BeeBenchmarkRequest -Context 4096 -PromptTokens 1024 -OutputTokens 1 -TimeoutSec 10
if($minimum.OutputTokens-ne16){throw "Expected output clamp to 16, got $($minimum.OutputTokens)"}
if($minimum.TimeoutSec-ne30){throw "Expected timeout clamp to 30, got $($minimum.TimeoutSec)"}

'BENCHMARK_LIMITS_TEST_OK'
