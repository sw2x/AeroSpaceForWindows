#requires -Version 7.0
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$SwiftArguments)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$swiftCommand = Get-Command swift.exe -ErrorAction SilentlyContinue
$localToolchain = Join-Path $repoRoot '.tools\swift\LocalApp\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin'
if ($swiftCommand) { $swiftExecutable = $swiftCommand.Source }
elseif (Test-Path (Join-Path $localToolchain 'swift.exe')) { $swiftExecutable = Join-Path $localToolchain 'swift.exe' }
else { throw 'Swift 6.4 is required. See README.md for installation.' }

$info = [Diagnostics.ProcessStartInfo]::new()
$info.FileName = $swiftExecutable
$info.WorkingDirectory = $repoRoot
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$info.RedirectStandardOutput = $true
$info.RedirectStandardError = $true
# Windows environment keys are case-insensitive, including for Swift subprocesses.
# Some shells inherit both Path and PATH; Swift rejects that duplicate.
$clean = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($entry in $info.Environment.GetEnumerator()) { $clean[$entry.Key] = $entry.Value }
$info.Environment.Clear()
foreach ($entry in $clean.GetEnumerator()) { $info.Environment[$entry.Key] = $entry.Value }

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (Test-Path $vswhere) {
    $vsRoot = & $vswhere -latest -version '[17.0,18.0)' -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($vsRoot) {
        $developerCommand = '"' + (Join-Path $vsRoot 'Common7\Tools\VsDevCmd.bat') + '" -no_logo -arch=x64 -host_arch=x64 >nul && set'
        $developerEnvironment = & $env:ComSpec /d /s /c $developerCommand
        foreach ($line in $developerEnvironment) {
            if ($line -match '^([^=]+)=(.*)$') { $info.Environment[$matches[1]] = $matches[2] }
        }
    }
}
$info.Environment['Path'] = (Split-Path $swiftExecutable) + ';' + $info.Environment['Path']
$info.Environment['CLANG_MODULE_CACHE_PATH'] = Join-Path $repoRoot '.build\clang-cache'
$info.Environment['SWIFTPM_MODULECACHE_OVERRIDE'] = Join-Path $repoRoot '.build\module-cache'
$iconDirectory = Join-Path $repoRoot 'Resources\Windows'
$iconResource = Join-Path $repoRoot '.build\resources\AeroSpace.res'
$info.Environment['AEROSPACE_ICON_RESOURCE'] = $iconResource
if ($SwiftArguments[0] -in @('build', 'test', 'run')) {
    $iconInputs = @((Join-Path $iconDirectory 'AeroSpace.rc'), (Join-Path $iconDirectory 'AeroSpace.ico'))
    $needsIconResource = !(Test-Path -LiteralPath $iconResource)
    if (!$needsIconResource) {
        $resourceTime = (Get-Item -LiteralPath $iconResource).LastWriteTimeUtc
        $needsIconResource = @($iconInputs | Where-Object { (Get-Item -LiteralPath $_).LastWriteTimeUtc -gt $resourceTime }).Count -gt 0
    }
    if ($needsIconResource) {
        $resourceCompiler = $info.Environment['Path'].Split(';') |
            Where-Object { $_ } | ForEach-Object { Join-Path $_ 'rc.exe' } |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
        if (!$resourceCompiler) {
            # Some Visual Studio installations omit the SDK bin directory from PATH.
            $sdkBinRoots = @((Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'))
            if ($info.Environment['WindowsSdkDir']) { $sdkBinRoots = @((Join-Path $info.Environment['WindowsSdkDir'] 'bin')) + $sdkBinRoots }
            $resourceCompiler = $sdkBinRoots | Select-Object -Unique |
                ForEach-Object { Get-ChildItem -LiteralPath $_ -Directory -ErrorAction SilentlyContinue } |
                Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
                Sort-Object { [version]$_.Name } -Descending |
                ForEach-Object { Join-Path $_.FullName 'x64\rc.exe' } |
                Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
        }
        if (!$resourceCompiler) { throw 'Windows SDK resource compiler rc.exe was not found in the Visual Studio environment.' }
        New-Item -ItemType Directory -Path (Split-Path $iconResource) -Force | Out-Null
        $resourceInfo = [Diagnostics.ProcessStartInfo]::new()
        $resourceInfo.FileName = $resourceCompiler
        $resourceInfo.WorkingDirectory = $iconDirectory
        $resourceInfo.UseShellExecute = $false
        $resourceInfo.CreateNoWindow = $true
        $resourceInfo.Environment.Clear()
        foreach ($entry in $info.Environment.GetEnumerator()) { $resourceInfo.Environment[$entry.Key] = $entry.Value }
        foreach ($argument in @('/nologo', '/fo', $iconResource, $iconInputs[0])) { $resourceInfo.ArgumentList.Add($argument) }
        $resourceProcess = [Diagnostics.Process]::Start($resourceInfo)
        $resourceProcess.WaitForExit()
        if ($resourceProcess.ExitCode -ne 0) { throw "Windows icon compilation failed: $($resourceProcess.ExitCode)" }
    }
}
# Derive the installed SDK without relying on installer changes reaching this process.
# An explicit existing SDKROOT takes precedence; administrative extraction is supported too.
$toolBin = Split-Path $swiftExecutable
$swiftRoot = Split-Path (Split-Path (Split-Path (Split-Path $toolBin)))
$installedSDK = Join-Path $swiftRoot 'Platforms\6.4.0\Windows.platform\Developer\SDKs\Windows.sdk'
$localSDK = Join-Path $env:TEMP 'aerospace-swift-sdk\LocalApp\Programs\Swift\Platforms\6.4.0\Windows.platform\Developer\SDKs\Windows.sdk'
$selectedSDK = $info.Environment['SDKROOT']
if (!$selectedSDK -or !(Test-Path -LiteralPath $selectedSDK -PathType Container)) {
    $sdkCandidates = @($installedSDK)
    if ($swiftExecutable.StartsWith($localToolchain, [StringComparison]::OrdinalIgnoreCase)) {
        $sdkCandidates = @($localSDK, $installedSDK)
    }
    $selectedSDK = $sdkCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Container } | Select-Object -First 1
}
if (!$selectedSDK) { throw 'Swift 6.4 Windows SDK was not found. Install the Windows platform component.' }
$info.Environment['SDKROOT'] = $selectedSDK
$info.Environment['SWIFTSDKROOT'] = $selectedSDK
$runtime = Join-Path (Split-Path (Split-Path $selectedSDK)) 'Library\XCTest-6.4.0\usr\bin64'
if (Test-Path -LiteralPath $runtime -PathType Container) {
    $info.Environment['Path'] += ';' + $runtime
}
foreach ($argument in $SwiftArguments) { $info.ArgumentList.Add($argument) }
if (!('AeroSpaceBuild.ErrorMode' -as [type])) {
    Add-Type -TypeDefinition 'namespace AeroSpaceBuild { public static class ErrorMode { [System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern uint SetErrorMode(uint mode); } }'
}
$oldErrorMode = [AeroSpaceBuild.ErrorMode]::SetErrorMode(3)
try { $process = [Diagnostics.Process]::Start($info) }
finally { [AeroSpaceBuild.ErrorMode]::SetErrorMode($oldErrorMode) | Out-Null }
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
$process.WaitForExit()
$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $stderrTask.GetAwaiter().GetResult()
if ($stdout) { Write-Output $stdout.TrimEnd() }
if ($stderr) { Write-Output $stderr.TrimEnd() }
if ($process.ExitCode -ne 0) { throw "swift exited with code $($process.ExitCode)" }
