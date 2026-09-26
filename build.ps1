#requires -Version 7.0
param([ValidateSet('debug','release')][string]$Configuration = 'debug', [switch]$Test)
$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot
Push-Location $repoRoot
try {
    & ./script/Invoke-Swift.ps1 build --build-system native -c $Configuration -j 4
    & ./script/Copy-Runtime.ps1 -Destination (Join-Path $repoRoot ".build\x86_64-unknown-windows-msvc\$Configuration") -IncludeTests:$Test
    if ($Test) {
        & ./script/Invoke-Swift.ps1 test --build-system native -c $Configuration -j 4
        & (Join-Path $repoRoot ".build\x86_64-unknown-windows-msvc\$Configuration\WindowsSmoke.exe")
        if ($LASTEXITCODE -ne 0) { throw "Windows smoke test failed: $LASTEXITCODE" }
    }
} finally { Pop-Location }
