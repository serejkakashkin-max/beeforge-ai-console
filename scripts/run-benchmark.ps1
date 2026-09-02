[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProfileId,
    [int]$PromptTokens = 4096,
    [int]$OutputTokens = 256,
    [int]$TimeoutSec = 900
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'BeeLlamaManager.Core.psm1') -Force
$paths = Get-BeeLogPaths
$profile = Get-BeeProfile $ProfileId
$apiBaseUrl = Get-BeeProfileApiBaseUrl $profile
$started = Get-Date

function Write-TestJson([string]$Path,$Value) {
    $temp = "$Path.tmp"
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $temp -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $Path -Force
}

try {
    Write-TestJson $paths.BenchmarkStatus ([pscustomobject]@{state='Preparing';message='Building deterministic prompt';startedAt=$started.ToString('o');targetPromptTokens=$PromptTokens;targetOutputTokens=$OutputTokens})
    $instruction = "`nThis is a throughput benchmark. Generate a long sequence of short numbered English words. Continue until the output limit. Do not explain the input and do not stop early."
    $seed = 'Benchmark data: alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima 0123456789. '
    $targetCharacters = [int][math]::Max(512,$PromptTokens*3)
    $synthetic = ''
    $measuredInput = 0
    for($sizeAttempt=0;$sizeAttempt-lt 4;$sizeAttempt++){
        $builder = New-Object Text.StringBuilder
        while($builder.Length-lt$targetCharacters){[void]$builder.Append($seed)}
        $synthetic=$builder.ToString(0,[math]::Min($builder.Length,$targetCharacters))
        $countBody=@{model=[string]$profile.alias;messages=@(@{role='user';content=$synthetic+$instruction});reasoning_effort='none';chat_template_kwargs=@{enable_thinking=$false}}|ConvertTo-Json -Depth 8
        $countResponse=Invoke-RestMethod -Uri "$apiBaseUrl/chat/completions/input_tokens" -Method Post -ContentType 'application/json; charset=utf-8' -Body $countBody -TimeoutSec 60
        $measuredInput=[int]$countResponse.input_tokens
        if($measuredInput-le 0){throw 'BeeLlama input_tokens endpoint returned an invalid token count'}
        if([math]::Abs($measuredInput-$PromptTokens)-le[math]::Max(8,$PromptTokens*0.01)){break}
        $targetCharacters=[int][math]::Max(256,[math]::Floor($targetCharacters*($PromptTokens/[double]$measuredInput)))
    }
    if(($measuredInput+$OutputTokens+128)-gt[int]$profile.context){throw "Measured input $measuredInput plus output $OutputTokens does not fit context $($profile.context)"}
    $body = @{
        model=[string]$profile.alias
        messages=@(@{role='user';content=$synthetic+$instruction})
        max_tokens=$OutputTokens
        temperature=0.7
        top_p=0.95
        stream=$false
        reasoning_effort='none'
        chat_template_kwargs=@{enable_thinking=$false}
    } | ConvertTo-Json -Depth 8
    Write-TestJson $paths.BenchmarkStatus ([pscustomobject]@{state='Running';message="Prompt processing / generation; measured input $measuredInput";startedAt=$started.ToString('o');targetPromptTokens=$PromptTokens;measuredInputTokens=$measuredInput;targetOutputTokens=$OutputTokens})
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-RestMethod -Uri "$apiBaseUrl/chat/completions" -Method Post -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec $TimeoutSec
    $watch.Stop()
    $promptActual = if ($response.timings.prompt_n) {[int]$response.timings.prompt_n} elseif ($response.usage.prompt_tokens) {[int]$response.usage.prompt_tokens} else {$null}
    $outputActual = if ($response.timings.predicted_n) {[int]$response.timings.predicted_n} elseif ($response.usage.completion_tokens) {[int]$response.usage.completion_tokens} else {$null}
    $promptTps = if ($response.timings.prompt_per_second) {[double]$response.timings.prompt_per_second} elseif ($response.timings.prompt_ms -and $promptActual) {$promptActual/([double]$response.timings.prompt_ms/1000.0)} else {$null}
    $decodeTps = if ($response.timings.predicted_per_second) {[double]$response.timings.predicted_per_second} elseif ($response.timings.predicted_ms -and $outputActual) {$outputActual/([double]$response.timings.predicted_ms/1000.0)} else {$null}
    $result = [pscustomobject]@{state='Completed';message='Benchmark completed';startedAt=$started.ToString('o');finishedAt=(Get-Date).ToString('o');elapsedSec=[math]::Round($watch.Elapsed.TotalSeconds,2);targetPromptTokens=$PromptTokens;targetOutputTokens=$OutputTokens;promptTokens=$promptActual;outputTokens=$outputActual;promptTps=$promptTps;decodeTps=$decodeTps;finishReason=$response.choices[0].finish_reason;contentPreview=([string]$response.choices[0].message.content).Substring(0,[math]::Min(300,([string]$response.choices[0].message.content).Length));timings=$response.timings;usage=$response.usage}
    Write-TestJson $paths.BenchmarkResult $result
    Write-TestJson $paths.BenchmarkStatus $result
} catch {
    Write-TestJson $paths.BenchmarkStatus ([pscustomobject]@{state='Failed';message=$_.Exception.Message;startedAt=$started.ToString('o');finishedAt=(Get-Date).ToString('o')})
    exit 1
} finally {
    Remove-Item -LiteralPath $paths.BenchmarkPid -Force -ErrorAction SilentlyContinue
}
