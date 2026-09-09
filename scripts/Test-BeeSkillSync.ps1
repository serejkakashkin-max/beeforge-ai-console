$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$temp=Join-Path ([IO.Path]::GetTempPath()) ('bee-skills-'+[guid]::NewGuid().ToString('N'))
try{
    $source=Join-Path $temp 'source';$target=Join-Path $temp 'target';$backup=Join-Path $temp 'backup'
    New-Item -ItemType Directory -Path "$source\one\references","$target\one\one" -Force|Out-Null
    [IO.File]::WriteAllText("$source\one\SKILL.md",'new skill')
    [IO.File]::WriteAllText("$source\one\references\guide.md",'new guide')
    [IO.File]::WriteAllText("$target\one\SKILL.md",'old skill')
    [IO.File]::WriteAllText("$target\one\one\SKILL.md",'nested stale')
    [IO.File]::WriteAllText("$target\one\custom.txt",'user extra')
    1..2|ForEach-Object{& (Join-Path $root 'scripts\Sync-BeeSkills.ps1') -SourceRoot $source -TargetRoot $target -BackupRoot $backup|Out-Null}
    if((Get-ChildItem -LiteralPath $target -Recurse -Filter SKILL.md).Count-ne1){throw 'Duplicate skill remains'}
    if([IO.File]::ReadAllText("$target\one\SKILL.md")-ne'new skill'){throw 'Root skill was not updated'}
    if(-not(Test-Path "$target\one\custom.txt")){throw 'User extra lost'}
    if((Get-ChildItem -LiteralPath $backup -Recurse -Filter SKILL.md).Count-ne2){throw 'Old and nested skills not backed up'}
    'SKILL_SYNC_TEST_OK'
}finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
