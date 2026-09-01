param(
    [Parameter(Mandatory=$true)][string]$Root
)

Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

$runnerLog=Join-Path $Root 'logs\telegram-runner.log'
try {
    $runnerParent=Split-Path $runnerLog -Parent;if(-not(Test-Path -LiteralPath $runnerParent)){New-Item -ItemType Directory -Path $runnerParent -Force|Out-Null}
    $localData=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if(-not$localData){throw 'LocalApplicationData is unavailable'}
    $state=Join-Path $Root 'runtime\telegram'
    $tool=Join-Path $Root 'tools\telegram-bridge\v1.0.0\bridge.mjs'
    $config=Join-Path $Root 'config\telegram.json'
    $token=Join-Path $Root 'secrets\telegram-token.dpapi'
    $key=Join-Path $Root 'secrets\telegram-bridge.key'
    $status=Join-Path $state 'status.json'
    $pidFile=Join-Path $state 'bridge.pid'
    $stopMarker=Join-Path $state 'manual-stop'
    $log=Join-Path $state 'telegram-bridge.log'
    $stdout=Join-Path $state 'bridge.stdout.log'
    $stderr=Join-Path $state 'bridge.stderr.log'
    New-Item -ItemType Directory -Path $state -Force|Out-Null
    [IO.File]::AppendAllText($runnerLog,("[{0:o}] runner_started identity={1} localData={2}`r`n" -f (Get-Date),[Security.Principal.WindowsIdentity]::GetCurrent().Name,$localData),[Text.UTF8Encoding]::new($false))
    if(-not(Test-Path -LiteralPath $config)){throw 'Telegram configuration is missing'}
    $bridgeConfig=[IO.File]::ReadAllText($config,[Text.UTF8Encoding]::new($false))|ConvertFrom-Json
    if(-not[bool]$bridgeConfig.enabled){
        [IO.File]::AppendAllText($runnerLog,("[{0:o}] runner_skipped reason=integration_disabled`r`n" -f (Get-Date)),[Text.UTF8Encoding]::new($false))
        exit 0
    }
    Add-Type -AssemblyName System.Security
    $node=Join-Path $env:ProgramFiles 'nodejs\node.exe'
    if(-not(Test-Path -LiteralPath $node)){$node=(Get-Command node.exe -ErrorAction Stop).Source}
    $quote={param([string]$Value) '"'+($Value-replace'"','\"')+'"'}
    $arguments=@(
        (&$quote $tool),'--config',(&$quote $config),'--token-file',(&$quote $token),'--key-file',(&$quote $key),
        '--token-stdin','true','--status',(&$quote $status),'--pid',(&$quote $pidFile),'--log',(&$quote $log)
    )
    $startInfo=New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName=$node
    $startInfo.Arguments=($arguments-join' ')
    $startInfo.WorkingDirectory=(Split-Path $tool -Parent)
    $startInfo.UseShellExecute=$false
    $startInfo.CreateNoWindow=$true
    $startInfo.RedirectStandardInput=$true
    while($true){
        if(Test-Path -LiteralPath $stopMarker){exit 0}
        $encryptedProbe=[IO.File]::ReadAllBytes($token)
        $plainProbe=[Security.Cryptography.ProtectedData]::Unprotect($encryptedProbe,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
        try{$tokenText=[Text.Encoding]::UTF8.GetString($plainProbe)}finally{[Array]::Clear($plainProbe,0,$plainProbe.Length)}
        $process=New-Object Diagnostics.Process
        $process.StartInfo=$startInfo
        if(-not$process.Start()){throw 'Node process did not start'}
        try{$process.StandardInput.Write($tokenText);$process.StandardInput.Close()}finally{$tokenText=$null}
        $process.WaitForExit()
        [IO.File]::AppendAllText($runnerLog,("[{0:o}] node_exited code={1}; restarting_in=3s`r`n" -f (Get-Date),$process.ExitCode),[Text.UTF8Encoding]::new($false))
        Start-Sleep -Seconds 3
        if(Test-Path -LiteralPath $stopMarker){exit 0}
    }
} catch {
    $parent=Split-Path $runnerLog -Parent;if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    [IO.File]::AppendAllText($runnerLog,("[{0:o}] runner_error: {1}`r`n" -f (Get-Date),$_.Exception.Message),[Text.UTF8Encoding]::new($false))
    exit 1
}
