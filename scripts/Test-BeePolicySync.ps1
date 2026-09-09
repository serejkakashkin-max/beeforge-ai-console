$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$temp=Join-Path ([IO.Path]::GetTempPath()) ('bee-policy-'+[guid]::NewGuid().ToString('N')+'.json')
try {
    $template=Get-Content (Join-Path $root 'opencode/opencode.template.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $template.agent.'software-engineer'.model='custom/provider'
    $template|Add-Member NoteProperty customSetting 'preserve'
    [IO.File]::WriteAllText($temp,($template|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($true))
    & (Join-Path $root 'tools/apply-serena-semantic-policy.ps1') -ConfigPath $temp | Out-Null
    $first=[IO.File]::ReadAllText($temp)
    & (Join-Path $root 'tools/apply-serena-semantic-policy.ps1') -ConfigPath $temp | Out-Null
    $actual=Get-Content $temp -Raw -Encoding UTF8|ConvertFrom-Json
    if($first-ne[IO.File]::ReadAllText($temp)){throw 'Policy application is not idempotent'}
    foreach($entry in $template.agent.PSObject.Properties){
        if($entry.Value.prompt-and$actual.agent.($entry.Name).prompt-ne$entry.Value.prompt){throw "Prompt drift: $($entry.Name)"}
    }
    if($actual.customSetting-ne'preserve'-or$actual.agent.'software-engineer'.model-ne'custom/provider'){throw 'Policy overwrote unrelated settings'}
    'POLICY_SYNC_TEST_OK'
} finally { if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp} }
