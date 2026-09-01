param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'

function Repair-Value($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) {
        # Only reverse the recognisable UTF-8-as-Windows-1251 mojibake pattern.
        # Correct Russian text is intentionally left untouched.
        if ($Value -match '[ЂЃЅІЇЊЋЌЎЏђѓєѕіїјљћќўџ]') {
            $candidate = [Text.Encoding]::UTF8.GetString([Text.Encoding]::GetEncoding(1251).GetBytes($Value))
            if ($candidate -match '[А-Яа-яЁё]') { return $candidate }
        }
        return $Value
    }
    if ($Value -is [System.Collections.IDictionary] -or $Value -is [pscustomobject]) {
        foreach ($property in @($Value.PSObject.Properties)) {
            $property.Value = Repair-Value $property.Value
        }
        return $Value
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        for ($i = 0; $i -lt $Value.Count; $i++) { $Value[$i] = Repair-Value $Value[$i] }
    }
    return $Value
}

$backup = "$ConfigPath.before-utf8-repair-$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item -LiteralPath $ConfigPath -Destination $backup -ErrorAction Stop
$config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding utf8 | ConvertFrom-Json
$config = Repair-Value $config
$json = $config | ConvertTo-Json -Depth 100
# Keep a BOM for compatibility with Windows editors and Windows PowerShell 5.1.
[IO.File]::WriteAllText($ConfigPath, $json, [Text.UTF8Encoding]::new($true))

$verified = Get-Content -LiteralPath $ConfigPath -Raw -Encoding utf8 | ConvertFrom-Json
if ((ConvertTo-Json $verified -Depth 100) -match '[ЂЃЅІЇЊЋЌЎЏђѓєѕіїјљћќўџ]') {
    throw 'UTF-8 repair verification failed; original configuration was preserved in backup.'
}
[pscustomobject]@{ repaired = $true; backup = $backup } | ConvertTo-Json -Compress
