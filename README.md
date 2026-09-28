# AeroSpace for Windows

English | [日本語](README.ja.md)

AeroSpace for Windows is an i3-style tiling window manager for **Windows 11 x64**, based on [Nikita Bobko's AeroSpace](https://github.com/nikitabobko/AeroSpace). This repository targets Windows only.

It retains AeroSpace's tree-based layouts, tiles and accordion layouts, floating windows, keyboard binding modes, multi-monitor support, TOML configuration, and CLI. The app runs in the system tray and manages windows through public Win32 APIs.

## Installation and startup

1. Extract `AeroSpace-Windows-x64.zip` to a folder you plan to keep. Keep the executables, DLLs, manifests, and resource folders together.
2. Run `AeroSpaceApp.exe`. Use its system tray menu to enable or disable window management, reload the configuration, or quit.
3. Run `aerospace.exe` from PowerShell to control the running app. Optionally, add the extracted folder to your user `PATH`.

```powershell
Start-Process .\AeroSpaceApp.exe
.\aerospace.exe list-windows --all
.\aerospace.exe workspace 2
.\aerospace.exe enable off
```

The app and CLI have different filenames because Windows filenames are case-insensitive. The ZIP includes the required Swift and Microsoft C++ runtimes; you do not need to install the Swift development tools to use it.

The AeroSpace taskbar button and system tray icon show the first one or two characters of the focused workspace name, such as `B`, `C`, `N`, or `1`. The button title and tray tooltip show the full name. Both icons show a dash when AeroSpace is disabled. To show text labels on taskbar buttons, set Windows' taskbar button combining option to Never.

AeroSpace workspaces are independent of Windows virtual desktops. Switching workspaces hides the windows on the previous workspace and shows the windows on the destination workspace. Each monitor has its own active workspace. Disabling or quitting AeroSpace restores the windows it has hidden. A separate watchdog process also restores them if the app exits unexpectedly. Recovery information is stored in `%LOCALAPPDATA%\AeroSpace`.

## Configuration

The app searches for a configuration in the following order and uses the first one it finds:

1. The file specified with `AeroSpaceApp.exe --config-path C:\path\aerospace.toml`.
2. `.aerospace.toml` in your home directory (`HOME`, or `USERPROFILE` if `HOME` is unset).
3. `%APPDATA%\AeroSpace\aerospace.toml`.
4. The bundled default configuration.

Copy [default-config.toml](docs/config-examples/default-config.toml) to your chosen configuration location. Set `auto-reload-config = true` to watch for changes and reload automatically, or run `aerospace reload-config` to reload manually. If a reload fails, the app reports the error and keeps the last valid configuration and key bindings. Hotkeys reserved by Windows or another app cannot be registered.

Available modifiers are `alt`, `ctrl`, `shift`, and `win`. The `exec-and-forget` command runs PowerShell scripts.

```toml
[mode.main.binding]
alt-enter = 'exec-and-forget Start-Process notepad.exe'
```

### Default key bindings

| Shortcut | Action |
| --- | --- |
| Alt + H / J / K / L | Focus the window to the left / below / above / right |
| Alt + Shift + H / J / K / L | Move the window left / down / up / right |
| Alt + 1…5 / B / C / N / O / Y | Switch workspaces |
| Alt + Shift + 1…5 / B / C / N / O / Y | Move the window to the specified workspace |
| Alt + Ctrl + B | Return to the previous workspace |
| Alt + / | Switch the tiles layout orientation |
| Alt + , | Switch the accordion layout orientation |
| Alt + Shift + Space | Switch between floating and tiling |
| Alt + F | Toggle AeroSpace fullscreen |
| Alt + − / = | Resize |
| Alt + Shift + ; | Enter service mode |
| Esc in service mode | Reload the configuration and return to main mode |

See the [Windows guide](docs/guide.adoc), [command reference](docs/commands.adoc), and `aerospace <command> --help` for details. Application IDs used in filters and output are executable filenames such as `notepad.exe`. Output fields include `%{app-id}`, `%{app-exec-path}`, and `%{app-executable-directory}`.

## Scope and limitations

- Creating or switching Windows virtual desktops, or moving windows between them, is not supported.
- `macos-native-fullscreen`, `macos-native-minimize`, `volume`, `move-mouse`, `subscribe`, and `debug-windows` are unavailable. The `fullscreen` command changes AeroSpace's layout.
- The configuration options `start-at-login`, `automatically-unhide-macos-hidden-apps`, and `focus-follows-mouse` are unsupported. Use Windows startup settings or a shortcut to launch the app automatically.
- The app manages eligible desktop windows in the current user session and Windows virtual desktop. Dialogs and windows that cannot be resized start floating; shell and tool windows are excluded.
- Windows focus restrictions and app minimum size requirements may prevent requested focus, position, or size changes. Managing windows belonging to apps running as administrator may require AeroSpace to run with the same privileges.
- Windows processes show and hide requests asynchronously, so recovery records are retained until their window or process identities become invalid. If an app later hides a recorded window itself, recovery may still show that window.

## Building and testing

Install Swift **6.4.0** for Windows, Visual Studio 2022 with the **Desktop development with C++** workload, and the Windows SDK. Run these commands from the repository folder using PowerShell 7 (`pwsh`):

```powershell
.\build.ps1 -Test
.\build-release.ps1
```

Debug executables are written to `.build\x86_64-unknown-windows-msvc\debug`, and the distribution ZIP to `.release\AeroSpace-Windows-x64.zip`. The test command runs Swift model and parser tests, plus Windows behavior checks using dedicated test windows. See the [development instructions](dev-docs/development.md) and [architecture](dev-docs/architecture.md).

## License and attribution

The original AeroSpace code and copyright notices are retained under the [MIT license](LICENSE.txt). Windows changes are distributed under the same license. See [legal](legal/README.md) for dependency licenses. This Windows port is a separate project from the original macOS project.
