[CmdletBinding()]
param([switch]$ValidateOnly,[switch]$Legacy)

$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$uiPath=[IO.Path]::GetFullPath((Join-Path $root 'ui\BeeLlama-Manager.ps1'))
$nextExe=[IO.Path]::GetFullPath((Join-Path $root 'local\BeeForge.Next\BeeForge.Next.App.exe'))
if($Legacy){
    if(-not(Test-Path -LiteralPath $uiPath -PathType Leaf)){throw "Не найден legacy-интерфейс BeeForge: $uiPath"}
    if($ValidateOnly){[pscustomobject]@{Valid=$true;Mode='Legacy';Path=$uiPath}|ConvertTo-Json -Compress;exit 0}
    $legacy=Start-Process -FilePath powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',('"'+$uiPath+'"')) -WorkingDirectory $root -PassThru
    [pscustomobject]@{Started=$true;Running=$true;Pid=$legacy.Id;Mode='Legacy';Message='BeeForge Legacy запущена'}|ConvertTo-Json -Compress
    exit 0
}
if(-not(Test-Path -LiteralPath $nextExe -PathType Leaf)){
    if($ValidateOnly){[pscustomobject]@{Valid=$false;Mode='Next';Path=$nextExe;Message='BeeForge Next ещё не опубликован'}|ConvertTo-Json -Compress;exit 1}
    & (Join-Path $PSScriptRoot 'Publish-BeeForgeNext.ps1') -Root $root | Out-Null
}

$existing=@(Get-CimInstance Win32_Process -Filter "Name='BeeForge.Next.App.exe'" -ErrorAction SilentlyContinue | Where-Object{
    -not[string]::IsNullOrWhiteSpace($_.ExecutablePath)-and[IO.Path]::GetFullPath($_.ExecutablePath)-eq$nextExe
})|Select-Object -First 1

if($ValidateOnly){
    [pscustomobject]@{Valid=$true;Mode='Next';Running=[bool]$existing;Pid=if($existing){[int]$existing.ProcessId}else{$null};Path=$nextExe}|ConvertTo-Json -Compress
    exit 0
}

if($existing){
    [pscustomobject]@{Started=$false;Running=$true;Pid=[int]$existing.ProcessId;Message='BeeForge AI Console уже запущена'}|ConvertTo-Json -Compress
    exit 0
}

$process=Start-Process -FilePath $nextExe -WorkingDirectory $root -PassThru
[pscustomobject]@{Started=$true;Running=$true;Pid=$process.Id;Mode='Next';Message='BeeForge AI Console запущена'}|ConvertTo-Json -Compress
