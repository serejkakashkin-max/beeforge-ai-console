[CmdletBinding()]
param([switch]$ValidateOnly)

$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$uiPath=[IO.Path]::GetFullPath((Join-Path $root 'ui\BeeLlama-Manager.ps1'))
if(-not(Test-Path -LiteralPath $uiPath -PathType Leaf)){throw "Не найден интерфейс BeeForge: $uiPath"}

$existing=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue | Where-Object{
    [string]$_.CommandLine -like "*$uiPath*"
})|Select-Object -First 1

if($ValidateOnly){
    [pscustomobject]@{Valid=$true;Running=[bool]$existing;Pid=if($existing){[int]$existing.ProcessId}else{$null};UiPath=$uiPath}|ConvertTo-Json -Compress
    exit 0
}

if($existing){
    [pscustomobject]@{Started=$false;Running=$true;Pid=[int]$existing.ProcessId;Message='BeeForge AI Console уже запущена'}|ConvertTo-Json -Compress
    exit 0
}

$powerShell=(Get-Command powershell.exe -ErrorAction Stop).Source
$process=Start-Process -FilePath $powerShell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',('"'+$uiPath+'"')) -WorkingDirectory $root -PassThru
[pscustomobject]@{Started=$true;Running=$true;Pid=$process.Id;Message='BeeForge AI Console запущена'}|ConvertTo-Json -Compress
