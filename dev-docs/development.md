# Windows development

## Requirements

- Windows 11 x64.
- Swift 6.4.0 Windows toolchain, including the Windows SDK and runtime components.
- Visual Studio 2022 with Desktop development with C++ and a Windows SDK.
- PowerShell 7 (`pwsh`). The build scripts locate Visual Studio using `vswhere` and import its compiler environment.

The repository's `.swift-version` and `Package.swift` define the Swift version. `script/Invoke-Swift.ps1` resolves `swift.exe`, supplies the compiler and SDK environment, and normalizes environment key casing. SwiftPM uses the native build engine explicitly.

## Build

```powershell
.\build.ps1
.\build.ps1 -Configuration release
```

Debug executables and resources are in `.build\x86_64-unknown-windows-msvc\debug`. `script/Copy-Runtime.ps1` copies Swift runtime assemblies, manifests and MSVC runtime DLLs beside the executables. Keep these files together when moving a build.

Start `AeroSpaceApp.exe` for the server and use `aerospace.exe` for the CLI. For a dedicated configuration:

```powershell
Start-Process .\.build\x86_64-unknown-windows-msvc\debug\AeroSpaceApp.exe -ArgumentList '--config-path', 'C:\configs\aerospace.toml'
```

`--read-only` starts discovery and query support without arranging windows or registering hotkeys. `--manage-process <PID>` restricts discovery to a fixture process and is useful for isolated diagnostics. Only one application instance can manage the same user session.

## Tests

```powershell
.\build.ps1 -Test
```

Swift tests cover command parsing, configuration, tree operations, layouts and monitor/workspace behavior using model fixtures. Windows XCTest discovery requires actor-isolated test methods to be asynchronous.

`WindowsSmoke.exe` creates a dedicated fixture process and windows. It checks native enumeration, geometry, hide/show, hotkey registration, named-pipe command handling, workspace visibility, rejected configuration reloads and watchdog recovery. The server is restricted to the fixture PID. Do not run this test while another AeroSpace instance owns the session.

For changes involving DPI, display removal or application-specific behavior, also check real applications and monitor arrangements. Native smoke tests use ordinary Win32 windows and do not cover every application's sizing constraints.

## Package

```powershell
.\build-release.ps1
```

The release script builds the app and CLI, copies resources and runtimes, checks CLI startup, and writes `.release\AeroSpace-Windows-x64.zip`. Keep dependency license notices in the package. The Windows GitHub Actions workflow runs build/tests and uploads this ZIP as a build artifact.

## Changes

Implement native platform calls in `Sources/NativeWindows`. Keep layout and workspace rules in the Swift model. Add tests when changes affect persistent state, visibility recovery, parser compatibility or command behavior. Update the command reference and built-in help together; the former macOS shell generation scripts are no longer part of the Windows build.
