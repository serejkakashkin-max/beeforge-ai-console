[CmdletBinding()]
param(
    [string]$Root=(Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent),
    [int]$Port=47656
)

$ErrorActionPreference='Stop'
$sample=Join-Path $Root 'runtime\telegram\voice\self-test.wav'
$key=[IO.File]::ReadAllText((Join-Path $Root 'secrets\telegram-bridge.key'),[Text.UTF8Encoding]::new($false)).Trim()

try {
    Add-Type -AssemblyName System.Speech
    Add-Type -AssemblyName System.Net.Http
    $speaker=New-Object System.Speech.Synthesis.SpeechSynthesizer
    try {
        $speaker.SetOutputToWaveFile($sample)
        $speaker.Speak('Bee Forge voice input works locally')
    } finally {$speaker.Dispose()}

    $client=[Net.Http.HttpClient]::new()
    try {
        [void]$client.DefaultRequestHeaders.Add('x-beeforge-key',$key)
        $form=[Net.Http.MultipartFormDataContent]::new()
        try {
            $stream=[IO.File]::OpenRead($sample)
            $audio=[Net.Http.StreamContent]::new($stream)
            $audio.Headers.ContentType=[Net.Http.Headers.MediaTypeHeaderValue]::new('audio/wav')
            $form.Add($audio,'file','self-test.wav')
            $form.Add([Net.Http.StringContent]::new('auto'),'language')
            $response=$client.PostAsync("http://127.0.0.1:$Port/v1/audio/transcriptions",$form).GetAwaiter().GetResult()
            $body=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            if(-not$response.IsSuccessStatusCode){throw "Voice Service HTTP $([int]$response.StatusCode): $body"}
            $result=$body|ConvertFrom-Json
            if([string]::IsNullOrWhiteSpace([string]$result.text)){throw 'Voice Service returned empty transcription'}
            Write-Output ("VOICE_TRANSCRIPTION_OK | language={0} | text={1}"-f$result.language,$result.text)
        } finally {$form.Dispose()}
    } finally {$client.Dispose()}
} finally {
    if(Test-Path -LiteralPath $sample){Remove-Item -LiteralPath $sample -Force}
    $key=$null
}
