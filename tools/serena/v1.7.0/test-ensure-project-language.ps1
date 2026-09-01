$ErrorActionPreference = 'Stop'
$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$helper = Join-Path $toolRoot 'ensure-project-language.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("beeforge-serena-test-" + [guid]::NewGuid().ToString('N'))

try {
    [IO.Directory]::CreateDirectory((Join-Path $testRoot '.serena')) | Out-Null
    [IO.File]::WriteAllText((Join-Path $testRoot 'main.ts'), "export const value = 1;`r`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $testRoot 'worker.py'), "value = 1`r`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllLines(
        (Join-Path $testRoot '.serena\project.yml'),
        @('project_name: "fixture"', 'language_servers:', '- typescript', 'encoding: "utf-8"'),
        [Text.UTF8Encoding]::new($true)
    )

    $first = (& $helper -ProjectPath $testRoot | ConvertFrom-Json)
    if ($first.status -ne 'extended' -or 'python' -notin @($first.added)) {
        throw "Expected Python extension, got: $($first | ConvertTo-Json -Compress)"
    }
    $second = (& $helper -ProjectPath $testRoot | ConvertFrom-Json)
    if ($second.status -ne 'already-configured') {
        throw "Expected idempotent configuration, got: $($second | ConvertTo-Json -Compress)"
    }
    $yaml = [IO.File]::ReadAllText((Join-Path $testRoot '.serena\project.yml'), [Text.UTF8Encoding]::new($false))
    if (($yaml -split "`r?`n" | Where-Object { $_ -eq '- typescript' }).Count -ne 1 -or
        ($yaml -split "`r?`n" | Where-Object { $_ -eq '- python' }).Count -ne 1) {
        throw 'Language server entries are missing or duplicated.'
    }
    if ($yaml -notmatch 'line_ending:\s*"crlf"') {
        throw 'Existing configuration did not receive the detected CRLF policy.'
    }

    $manifestRoot = Join-Path $testRoot 'manifest-only'
    [IO.Directory]::CreateDirectory($manifestRoot) | Out-Null
    [IO.File]::WriteAllText((Join-Path $manifestRoot 'package.json'), '{"private":true}', [Text.UTF8Encoding]::new($false))
    $manifest = (& $helper -ProjectPath $manifestRoot | ConvertFrom-Json)
    $manifestYaml = [IO.File]::ReadAllText((Join-Path $manifestRoot '.serena\project.yml'), [Text.UTF8Encoding]::new($false))
    if ($manifest.status -ne 'created' -or 'typescript' -notin @($manifest.language_servers) -or
        $manifestYaml -notmatch '# beeforge_managed_language_servers: true' -or
        $manifestYaml -notmatch 'line_ending:\s*"lf"') {
        throw "Manifest-only project was not prepared correctly: $($manifest | ConvertTo-Json -Compress)"
    }

    [IO.File]::WriteAllText((Join-Path $manifestRoot 'worker.py'), "value = 1`n", [Text.UTF8Encoding]::new($false))
    Remove-Item -LiteralPath (Join-Path $manifestRoot 'package.json') -Force
    $reconciled = (& $helper -ProjectPath $manifestRoot | ConvertFrom-Json)
    if ($reconciled.status -ne 'reconciled' -or @($reconciled.language_servers) -ne 'python' -or
        'typescript' -notin @($reconciled.removed)) {
        throw "Managed languages were not reconciled: $($reconciled | ConvertTo-Json -Compress)"
    }

    [pscustomobject]@{
        passed = $true
        legacyFirst = $first.status
        legacySecond = $second.status
        legacyLanguages = @($second.language_servers)
        manifest = $manifest.status
        reconciled = $reconciled.status
        managedLanguages = @($reconciled.language_servers)
    } | ConvertTo-Json -Compress
} finally {
    $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $resolvedTest = [IO.Path]::GetFullPath($testRoot)
    if ($resolvedTest.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase) -and
        $resolvedTest -ne $resolvedTemp -and (Test-Path -LiteralPath $resolvedTest)) {
        Remove-Item -LiteralPath $resolvedTest -Recurse -Force
    }
}
