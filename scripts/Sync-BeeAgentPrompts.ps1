param([string]$ConfigPath=(Join-Path $env:USERPROFILE '.config\opencode\opencode.json'))
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$template=Get-Content (Join-Path $root 'opencode/opencode.template.json') -Raw -Encoding UTF8|ConvertFrom-Json
$config=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8|ConvertFrom-Json
foreach($entry in $template.agent.PSObject.Properties){
    if($entry.Value.prompt -and $config.agent.PSObject.Properties[$entry.Name]){
        $config.agent.($entry.Name).prompt=$entry.Value.prompt
    }
}
Copy-Item -LiteralPath $ConfigPath -Destination ($ConfigPath+'.before-prompts-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.bak')
[IO.File]::WriteAllText($ConfigPath,($config|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))
'AGENT_PROMPTS_SYNC_OK (permissions, providers and models preserved)'
