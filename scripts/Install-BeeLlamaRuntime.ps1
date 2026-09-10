[CmdletBinding()]
param(
    [string]$Version = 'v0.4.6',
    [ValidateSet('13.3','12.4')]
    [string]$CudaVersion = '13.3',
    [switch]$UpdateProfiles,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'BeeLlama runtime installer supports Windows only.' }

$script:Root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$normalizedVersion = if ($Version.StartsWith('v',[StringComparison]::OrdinalIgnoreCase)) { $Version } else { 'v' + $Version }
if ($normalizedVersion -notmatch '^v\d+\.\d+\.\d+$') { throw "Unsupported BeeLlama version format: $Version" }
$targetDirectory = Join-Path $script:Root ("runtime\beellama-{0}-cuda{1}" -f $normalizedVersion,$CudaVersion)
$serverPath = Join-Path $targetDirectory 'llama-server.exe'
$releaseApi = "https://api.github.com/repos/Anbeeld/beellama.cpp/releases/tags/$normalizedVersion"
$headers = @{
    'Accept' = 'application/vnd.github+json'
    'User-Agent' = 'BeeForge-AI-Console'
    'X-GitHub-Api-Version' = '2022-11-28'
}

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Get-ReleaseAsset($Release,[string]$ExactName,[string]$FallbackPattern='') {
    $matches = @($Release.assets | Where-Object { [string]$_.name -eq $ExactName })
    if ($matches.Count -eq 0 -and $FallbackPattern) {
        $matches = @($Release.assets | Where-Object { [string]$_.name -like $FallbackPattern })
    }
    if ($matches.Count -ne 1) {
        $names = @($Release.assets | ForEach-Object { [string]$_.name }) -join ', '
        throw "Expected exactly one release asset '$ExactName'. Matching assets: $($matches.Count). Release assets: $names"
    }
    $asset = $matches[0]
    $digest = [string]$asset.digest
    if ($digest -notmatch '^sha256:[0-9a-fA-F]{64}$') {
        throw "GitHub release asset '$($asset.name)' does not expose a SHA-256 digest; refusing an unverified runtime download."
    }
    return $asset
}

function Save-VerifiedAsset($Asset,[string]$Destination) {
    $expected = ([string]$Asset.digest).Substring(7).ToLowerInvariant()
    Write-Host ("Downloading {0} ({1:N1} MiB)..." -f $Asset.name,([double]$Asset.size/1MB))
    Invoke-WebRequest -Uri ([string]$Asset.browser_download_url) -OutFile $Destination -Headers $headers -UseBasicParsing
    $actual = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) {
        throw "SHA-256 mismatch for $($Asset.name). Expected $expected, got $actual"
    }
    Write-Host "SHA-256 verified: $actual" -ForegroundColor Green
}

function Copy-DirectoryContents([string]$Source,[string]$Destination) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    foreach ($item in @(Get-ChildItem -LiteralPath $Source -Force)) {
        Copy-Item -LiteralPath $item.FullName -Destination $Destination -Recurse -Force
    }
}

function Update-ManagedProfiles([string]$NewServerPath) {
    $profilesPath = Join-Path $script:Root 'config\profiles.json'
    if (-not (Test-Path -LiteralPath $profilesPath -PathType Leaf)) {
        Write-Warning 'config\profiles.json was not found; runtime installed but no profiles were changed.'
        return 0
    }

    $json = [IO.File]::ReadAllText($profilesPath,[Text.UTF8Encoding]::new($false))
    $store = $json | ConvertFrom-Json
    $managedPrefix = [IO.Path]::GetFullPath((Join-Path $script:Root 'runtime\beellama-'))
    $changed = 0

    foreach ($profile in @($store.profiles)) {
        $mode = if ($profile.PSObject.Properties['connectionMode']) { [string]$profile.connectionMode } else { 'LocalHost' }
        if ($mode -ne 'LocalHost') { continue }

        $current = if ($profile.PSObject.Properties['serverPath']) { [string]$profile.serverPath } else { '' }
        $managed = [string]::IsNullOrWhiteSpace($current)
        if (-not $managed) {
            try {
                $currentFull = [IO.Path]::GetFullPath($current)
                $managed = $currentFull.StartsWith($managedPrefix,[StringComparison]::OrdinalIgnoreCase)
            } catch { $managed = $false }
        }
        if (-not $managed) {
            Write-Host "Keeping custom runtime for profile '$($profile.name)': $current"
            continue
        }

        if ($profile.PSObject.Properties['serverPath']) { $profile.serverPath = $NewServerPath }
        else { $profile | Add-Member -NotePropertyName serverPath -NotePropertyValue $NewServerPath }
        $changed++
    }

    if ($changed -gt 0) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        Copy-Item -LiteralPath $profilesPath -Destination "$profilesPath.before-beellama-$stamp" -Force
        $tempPath = "$profilesPath.tmp"
        $outJson = $store | ConvertTo-Json -Depth 100
        [IO.File]::WriteAllText($tempPath,$outJson + [Environment]::NewLine,[Text.UTF8Encoding]::new($true))
        Move-Item -LiteralPath $tempPath -Destination $profilesPath -Force
    }
    return $changed
}

function Invoke-NativeVersionProbe([string]$Path) {
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Path
    $startInfo.Arguments = '--version'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            return [pscustomobject]@{ ExitCode = -1; Output = 'Process.Start returned false.' }
        }
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        return [pscustomobject]@{
            ExitCode = [int]$process.ExitCode
            Output = (($stdout + [Environment]::NewLine + $stderr).Trim())
        }
    } finally {
        $process.Dispose()
    }
}

function Test-InstalledRuntime([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath (Join-Path $directory 'ggml-cuda.dll') -PathType Leaf)) { return $false }
    try {
        # Do not invoke the native executable through PowerShell's 2>&1 redirection here.
        # Windows PowerShell 5.1 can promote native stderr into NativeCommandError when
        # $ErrorActionPreference='Stop', even when llama-server exits successfully.
        $probe = Invoke-NativeVersionProbe $Path
        if ($probe.ExitCode -ne 0) { return $false }
        if ([string]::IsNullOrWhiteSpace([string]$probe.Output)) { return $false }
        return ([string]$probe.Output -match '(?im)^version:\s+\S+')
    } catch {
        return $false
    }
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ($Force -and (Test-Path -LiteralPath $targetDirectory)) {
    Write-Step "Removing existing BeeLlama $normalizedVersion CUDA $CudaVersion runtime"
    Remove-Item -LiteralPath $targetDirectory -Recurse -Force
}

if (-not (Test-InstalledRuntime $serverPath)) {
    Write-Step "Resolving BeeLlama $normalizedVersion CUDA $CudaVersion release assets"
    $release = Invoke-RestMethod -Uri $releaseApi -Headers $headers -UseBasicParsing
    if ([string]$release.tag_name -ne $normalizedVersion) { throw "Unexpected release tag: $($release.tag_name)" }

    $binaryName = "beellama-$normalizedVersion-bin-win-cuda-$CudaVersion-x64.zip"
    $cudartName = "beellama-$normalizedVersion-cudart-win-cuda-$CudaVersion-x64.zip"
    $binaryAsset = Get-ReleaseAsset $release $binaryName "*-bin-win-cuda-$CudaVersion-x64.zip"
    $cudartAsset = Get-ReleaseAsset $release $cudartName "*-cudart-win-cuda-$CudaVersion-x64.zip"

    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('beeforge-beellama-' + [guid]::NewGuid().ToString('N'))
    $binArchive = Join-Path $tempRoot 'beellama-bin.zip'
    $cudaArchive = Join-Path $tempRoot 'beellama-cudart.zip'
    $binStage = Join-Path $tempRoot 'bin'
    $cudaStage = Join-Path $tempRoot 'cudart'
    New-Item -ItemType Directory -Path $tempRoot,$binStage,$cudaStage -Force | Out-Null

    try {
        Save-VerifiedAsset $binaryAsset $binArchive
        Save-VerifiedAsset $cudaAsset $cudaArchive

        Write-Step 'Extracting BeeLlama runtime'
        Expand-Archive -LiteralPath $binArchive -DestinationPath $binStage -Force
        Expand-Archive -LiteralPath $cudaArchive -DestinationPath $cudaStage -Force

        $stagedServer = Get-ChildItem -LiteralPath $binStage -Recurse -File -Filter 'llama-server.exe' | Select-Object -First 1
        if (-not $stagedServer) { throw 'llama-server.exe was not found inside the BeeLlama Windows CUDA archive.' }
        $stagedCudaBackend = Get-ChildItem -LiteralPath $binStage -Recurse -File -Filter 'ggml-cuda.dll' | Select-Object -First 1
        if (-not $stagedCudaBackend) { throw 'ggml-cuda.dll was not found inside the BeeLlama Windows CUDA archive.' }

        New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
        Copy-DirectoryContents $stagedServer.Directory.FullName $targetDirectory

        foreach ($file in @(Get-ChildItem -LiteralPath $cudaStage -Recurse -File)) {
            Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $targetDirectory $file.Name) -Force
        }

        if (-not (Test-InstalledRuntime $serverPath)) {
            throw "BeeLlama runtime was extracted but '$serverPath --version' did not start successfully."
        }

        $manifest = [ordered]@{
            product = 'BeeLlama.cpp'
            version = $normalizedVersion
            cudaVersion = $CudaVersion
            installedAt = (Get-Date).ToString('o')
            repository = 'Anbeeld/beellama.cpp'
            binaryAsset = [ordered]@{ name=[string]$binaryAsset.name; digest=[string]$binaryAsset.digest }
            cudartAsset = [ordered]@{ name=[string]$cudartAsset.name; digest=[string]$cudartAsset.digest }
        }
        [IO.File]::WriteAllText((Join-Path $targetDirectory 'beeforge-runtime.json'),($manifest | ConvertTo-Json -Depth 6) + [Environment]::NewLine,[Text.UTF8Encoding]::new($false))
    } finally {
        if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }
} else {
    Write-Host "BeeLlama $normalizedVersion CUDA $CudaVersion is already installed: $serverPath" -ForegroundColor Green
}

if ($UpdateProfiles) {
    Write-Step 'Switching BeeForge-managed LocalHost profiles to the installed runtime'
    $updated = Update-ManagedProfiles $serverPath
    Write-Host "Profiles updated: $updated" -ForegroundColor Green
}

Write-Step 'BeeLlama runtime ready'
Write-Host $serverPath -ForegroundColor Green
Write-Output $serverPath
