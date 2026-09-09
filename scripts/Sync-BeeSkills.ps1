param(
    [string]$SourceRoot=(Join-Path (Split-Path $PSScriptRoot -Parent) 'opencode\skills'),
    [string]$TargetRoot=(Join-Path $env:USERPROFILE '.agents\skills'),
    [string]$BackupRoot=(Join-Path (Split-Path $PSScriptRoot -Parent) 'backups\skills')
)
$ErrorActionPreference='Stop'
$sourceFull=[IO.Path]::GetFullPath($SourceRoot).TrimEnd('\','/')
$targetFull=[IO.Path]::GetFullPath($TargetRoot).TrimEnd('\','/')
if($sourceFull-eq$targetFull){throw 'Source and target must differ'}
$stamp=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
foreach($source in Get-ChildItem -LiteralPath $sourceFull -Directory){
    if($source.Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'Linked skill source is not supported'}
    $destination=Join-Path $targetFull $source.Name
    New-Item -ItemType Directory -Path $destination -Force|Out-Null
    if((Get-Item -LiteralPath $destination).Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'Linked skill target is not supported'}
    $nested=[IO.Path]::GetFullPath((Join-Path $destination $source.Name))
    if(Test-Path -LiteralPath (Join-Path $nested 'SKILL.md')){
        if(-not$nested.StartsWith($targetFull+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Nested skill outside target'}
        if((Get-Item -LiteralPath $nested).Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'Linked nested skill is not supported'}
        $backup=Join-Path $BackupRoot "$($source.Name)-nested-$stamp"
        New-Item -ItemType Directory -Path $BackupRoot -Force|Out-Null
        Move-Item -LiteralPath $nested -Destination $backup
    }
    foreach($file in Get-ChildItem -LiteralPath $source.FullName -Recurse -File){
        $relative=$file.FullName.Substring($source.FullName.Length).TrimStart('\','/')
        $target=Join-Path $destination $relative
        $parent=Split-Path $target -Parent
        New-Item -ItemType Directory -Path $parent -Force|Out-Null
        if(Test-Path -LiteralPath $target){
            if((Get-FileHash -LiteralPath $target).Hash-eq(Get-FileHash -LiteralPath $file.FullName).Hash){continue}
            $backup=Join-Path (Join-Path $BackupRoot "$($source.Name)-previous-$stamp") $relative
            New-Item -ItemType Directory -Path (Split-Path $backup -Parent) -Force|Out-Null
            Copy-Item -LiteralPath $target -Destination $backup
        }
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force
    }
}
'BEE_SKILLS_SYNC_OK'
