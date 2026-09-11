param(
    [Parameter(Mandatory=$true)][string]$KeyFile,
    [string]$ConfigPath=(Join-Path $env:USERPROFILE '.config\opencode\opencode.json')
)
$ErrorActionPreference='Stop'
$key=[IO.File]::ReadAllText((Resolve-Path -LiteralPath $KeyFile)).Trim()
if($key -notmatch '^sk-[A-Za-z0-9_-]+$'){throw 'Expected one API key in KeyFile'}
$config=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8|ConvertFrom-Json
$secretDir=Join-Path (Split-Path $ConfigPath -Parent) 'secrets'
New-Item -ItemType Directory -Path $secretDir -Force|Out-Null
$secretPath=Join-Path $secretDir 'vyce-api-key.txt'
# Restrict the directory before writing the plaintext file required by OpenCode.
$acl=New-Object Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true,$false)
$identity=[Security.Principal.WindowsIdentity]::GetCurrent().User
foreach($sid in @($identity,[Security.Principal.SecurityIdentifier]::new('S-1-5-18'))){
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow'))
}
Set-Acl -LiteralPath $secretDir -AclObject $acl
if(Test-Path -LiteralPath $secretPath){
    $fileAcl=New-Object Security.AccessControl.FileSecurity
    $fileAcl.SetAccessRuleProtection($true,$false)
    foreach($sid in @($identity,[Security.Principal.SecurityIdentifier]::new('S-1-5-18'))){$fileAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,'FullControl','Allow'))}
    Set-Acl -LiteralPath $secretPath -AclObject $fileAcl
}
[IO.File]::WriteAllText($secretPath,$key,[Text.UTF8Encoding]::new($false))
$key=$null
$models=[ordered]@{}
foreach($entry in @(
    @('gpt-5.6-new',270000),@('claude-sonnet-4-6',200000),
    @('deepseek-v4-flash',128000),@('deepseek-v4-flash-lr',32768),
    @('nemotron-ultra-550b',128000),@('nemotron-vision',128000)
)){
    # Provider /models reports context, not output caps. Use a conservative
    # 4096-token output budget; LR context is conservative until documented.
    $models[$entry[0]]=@{name=('Vyce AI / '+$entry[0]);limit=@{context=$entry[1];output=4096}}
}
$provider=@{npm='@ai-sdk/openai-compatible';name='Vyce AI';options=@{baseURL='https://vyceai.com/v1';apiKey=('{file:'+($secretPath -replace '\\','/')+'}');timeout=120000};models=$models}
if(-not $config.PSObject.Properties['provider']){$config|Add-Member NoteProperty provider ([pscustomobject]@{})}
$config.provider|Add-Member NoteProperty vyce $provider -Force
Copy-Item -LiteralPath $ConfigPath -Destination ($ConfigPath+'.before-vyce-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.bak')
[IO.File]::WriteAllText($ConfigPath,($config|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))
Write-Output 'Vyce AI configured. Existing default and agent models preserved. Restart OpenCode to reload.'
