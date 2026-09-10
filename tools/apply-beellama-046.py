from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read_preserve(path: Path):
    data = path.read_bytes()
    bom = data.startswith(b'\xef\xbb\xbf')
    text = data.decode('utf-8-sig')
    return text, bom


def write_preserve(path: Path, text: str, bom: bool):
    enc = 'utf-8-sig' if bom else 'utf-8'
    path.write_text(text, encoding=enc, newline='')


def replace_exact(path: Path, old: str, new: str, min_count=1, max_count=None):
    text, bom = read_preserve(path)
    count = text.count(old)
    if count < min_count or (max_count is not None and count > max_count):
        raise SystemExit(f'{path}: expected {min_count}..{max_count or "many"} matches, got {count}: {old!r}')
    text = text.replace(old, new)
    write_preserve(path, text, bom)
    print(f'patched {path.relative_to(ROOT)} ({count} replacement(s))')


core = ROOT / 'scripts' / 'BeeLlamaManager.Core.psm1'
replace_exact(
    core,
    "runtime\\beellama-v0.4.3-cuda13.1\\llama-server.exe",
    "runtime\\beellama-v0.4.6-cuda13.3\\llama-server.exe",
    min_count=1,
    max_count=1,
)

profiles = ROOT / 'config' / 'templates' / 'profiles.example.json'
replace_exact(
    profiles,
    'beellama-v0.4.3-cuda13.1',
    'beellama-v0.4.6-cuda13.3',
    min_count=2,
)

installer = ROOT / 'scripts' / 'Install-BeeForge.ps1'
text, bom = read_preserve(installer)
nl = '\r\n' if '\r\n' in text else '\n'
param_old = nl.join([
    '    [switch]$SkipDependencies,',
    '    [switch]$Force',
    ')',
])
param_new = nl.join([
    '    [switch]$SkipDependencies,',
    '    [switch]$SkipBeeLlamaRuntime,',
    '    [switch]$Force',
    ')',
])
if param_old not in text:
    raise SystemExit('Install-BeeForge.ps1: parameter anchor not found')
text = text.replace(param_old, param_new, 1)
anchor = nl.join([
    '    Write-JsonUtf8 $profilesPath $profiles',
    '}',
    '',
    "$telegramPath = Join-Path $script:Root 'config\\telegram.json'",
])
block = nl.join([
    '    Write-JsonUtf8 $profilesPath $profiles',
    '}',
    '',
    "if ($Mode -eq 'LocalHost' -and -not $LlamaServerPath -and -not $SkipBeeLlamaRuntime) {",
    "    Write-Step 'Установка BeeLlama v0.4.6 CUDA 13.3'",
    "    $runtimeInstaller = Join-Path $script:Root 'scripts\\Install-BeeLlamaRuntime.ps1'",
    "    & $runtimeInstaller -Version 'v0.4.6' -CudaVersion '13.3' -UpdateProfiles | Out-Null",
    '}',
    '',
    "$telegramPath = Join-Path $script:Root 'config\\telegram.json'",
])
if anchor not in text:
    raise SystemExit('Install-BeeForge.ps1: profile-write anchor not found')
text = text.replace(anchor, block, 1)
write_preserve(installer, text, bom)
print('patched scripts/Install-BeeForge.ps1')

readme = ROOT / 'README.md'
text, bom = read_preserve(readme)
marker = '## BeeLlama runtime updates'
if marker not in text:
    section = r'''

## BeeLlama runtime updates

BeeForge pins the default local runtime to **BeeLlama v0.4.6 CUDA 13.3** on Windows/NVIDIA. The runtime is installed into `runtime\beellama-v0.4.6-cuda13.3` and older runtime folders are kept for rollback.

For an existing installation, pull the repository and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-BeeLlamaRuntime.ps1 -Version v0.4.6 -CudaVersion 13.3 -UpdateProfiles
```

The installer resolves the official `Anbeeld/beellama.cpp` release assets through the GitHub API, downloads both the Windows CUDA binary archive and matching CUDA runtime archive, verifies each asset against the SHA-256 digest published by GitHub, validates that `llama-server.exe --version` starts, and only then switches BeeForge-managed LocalHost profiles. A profile using a custom `llama-server.exe` outside BeeForge's `runtime\beellama-*` folders is left unchanged.

To reinstall the same runtime from scratch, add `-Force`. To keep a custom runtime during a full `Install-BeeForge.ps1` run, pass `-LlamaServerPath`; to skip BeeLlama installation entirely, pass `-SkipBeeLlamaRuntime`.
'''
    text = text.rstrip() + section + '\n'
    write_preserve(readme, text, bom)
    print('patched README.md')
else:
    print('README.md already contains BeeLlama runtime section')
