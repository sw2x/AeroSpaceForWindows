#requires -Version 7.0
$ErrorActionPreference = 'Stop'
& "$PSScriptRoot\build.ps1" -Configuration release
Push-Location $PSScriptRoot
try {
    $workspaceRoot = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\'
    $releaseRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.release'))
    $output = [IO.Path]::GetFullPath((Join-Path $releaseRoot 'AeroSpace'))
    if (!$output.StartsWith($workspaceRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $output -ne (Join-Path $releaseRoot 'AeroSpace')) { throw 'Invalid release output path' }
    foreach ($path in @($releaseRoot, $output)) {
        if ((Test-Path -LiteralPath $path) -and
            ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Refusing to overwrite a linked release directory: $path"
        }
    }
    if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Recurse -Force }
    New-Item -ItemType Directory -Path $output -Force | Out-Null
    $binaryDirectory = Join-Path $PSScriptRoot '.build\x86_64-unknown-windows-msvc\release'
    foreach ($name in @('AeroSpaceApp.exe', 'aerospace.exe')) { Copy-Item -LiteralPath (Join-Path $binaryDirectory $name) -Destination $output }
    Get-ChildItem $binaryDirectory -Directory -Filter '*.resources' | Copy-Item -Destination $output -Recurse -Force
    & ./script/Copy-Runtime.ps1 -Destination $output
    Copy-Item LICENSE.txt, README.md, README.ja.md -Destination $output -Force
    Copy-Item legal, docs, dev-docs -Destination $output -Recurse -Force
    Copy-Item Sources/AppBundle/Resources/default-config.toml -Destination $output -Force
    $smoke = & (Join-Path $output 'aerospace.exe') --help
    if ($LASTEXITCODE -ne 0 -or !$smoke) { throw 'Packaged CLI failed its startup check' }
    Compress-Archive -Path $output -DestinationPath (Join-Path $PSScriptRoot '.release\AeroSpace-Windows-x64.zip') -Force
} finally { Pop-Location }
