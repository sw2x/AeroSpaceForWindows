#requires -Version 7.0
param([Parameter(Mandatory=$true)][string]$Destination, [switch]$IncludeTests)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$swift = Get-Command swift.exe -ErrorAction SilentlyContinue
if ($swift) { $toolBin = Split-Path $swift.Source }
else { $toolBin = Join-Path $repoRoot '.tools\swift\LocalApp\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin' }
$swiftRoot = Split-Path (Split-Path (Split-Path (Split-Path $toolBin)))
$runtimeBin = Join-Path $swiftRoot 'Runtimes\6.4.0\usr\bin'
New-Item -ItemType Directory -Path $Destination -Force | Out-Null
$names = @('_FoundationICU','BlocksRuntime','dispatch','Foundation','FoundationEssentials',
    'FoundationInternationalization','FoundationNetworking','FoundationXML','swiftCore','swiftCRT',
    'swiftDispatch','swift_Concurrency','swift_RegexParser','swift_StringProcessing','swiftSwiftOnoneSupport',
    'swiftObservation','swiftSynchronization','swiftWinSDK','swiftRegexBuilder')
foreach ($name in $names) {
    $candidates = @((Join-Path $runtimeBin "$name.dll"), (Join-Path $runtimeBin "$name\$name.dll"),
        (Join-Path $toolBin "$name.dll"), (Join-Path $toolBin "$name\$name.dll"))
    $dll = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (!$dll) { throw "Swift runtime $name.dll was not found in $toolBin" }
    Copy-Item -LiteralPath $dll -Destination $Destination -Force
    $manifest = '<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0"><assemblyIdentity type="win32" name="'+$name+'" version="6.4.0.0" processorArchitecture="amd64"/><file name="'+$name+'.dll"/></assembly>'
    [IO.File]::WriteAllText((Join-Path $Destination "$name.manifest"), $manifest)
}
if ($IncludeTests) {
    $libraries = @((Join-Path $swiftRoot 'Platforms\6.4.0\Windows.platform\Developer\Library'),
        (Join-Path $env:TEMP 'aerospace-swift-sdk\LocalApp\Programs\Swift\Platforms\6.4.0\Windows.platform\Developer\Library'))
    foreach ($library in $libraries) {
        if (!(Test-Path -LiteralPath $library)) { continue }
        Get-ChildItem $library -Directory | Where-Object { $_.Name -match '^(XCTest|Testing)-' } | ForEach-Object {
            $bin = Join-Path $_.FullName 'usr\bin64'
            if (Test-Path -LiteralPath $bin) {
                Get-ChildItem $bin -Filter '*.dll' | ForEach-Object {
                    Copy-Item -LiteralPath $_.FullName -Destination $Destination -Force
                    $manifest = '<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0"><assemblyIdentity type="win32" name="'+$_.BaseName+'" version="6.4.0.0" processorArchitecture="amd64"/><file name="'+$_.Name+'"/></assembly>'
                    [IO.File]::WriteAllText((Join-Path $Destination ($_.BaseName+'.manifest')), $manifest)
                }
            }
        }
    }
}
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vsRoot = & $vswhere -latest -version '[17.0,18.0)' -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$vsRoot) { throw 'Visual Studio 2022 with the x64 C++ toolchain was not found' }
$crt = Get-ChildItem (Join-Path $vsRoot 'VC\Redist\MSVC') -Directory | Where-Object { $_.Name -match '^\d' } | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if (!$crt) { throw 'MSVC redistributable files were not found' }
Get-ChildItem (Join-Path $crt.FullName 'x64\Microsoft.VC143.CRT') -Filter '*.dll' | Copy-Item -Destination $Destination -Force
