param([Parameter(Mandatory=$true)][string]$Path)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Security
$encrypted=[IO.File]::ReadAllBytes($Path)
$plain=[Security.Cryptography.ProtectedData]::Unprotect($encrypted,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
try{[Console]::Out.Write([Text.Encoding]::UTF8.GetString($plain))}finally{[Array]::Clear($plain,0,$plain.Length)}
