# Windows architecture

## Components

| Directory | Responsibility |
| --- | --- |
| `Sources/AeroSpaceApp` | Windows application entry point and watchdog mode |
| `Sources/AppBundle` | Workspace tree, layouts, command execution, configuration, events and tray state |
| `Sources/Common` | CLI argument parsers, help, JSON protocol and named-pipe connection |
| `Sources/Cli` | `aerospace.exe` client |
| `Sources/NativeWindows` | C bridge to public Windows APIs |
| `Sources/AppBundleTests` | Swift model and parser tests |
| `Tests/WindowsSmoke` | Native integration test and isolated fixture windows |

`Package.swift` builds both executables using SwiftPM. The retained `AppBundle` target name denotes the application logic library; it does not create an Apple app bundle.

## Window model and events

The native bridge enumerates eligible top-level HWNDs and monitors, obtains process identity and visible frame bounds, and exposes focus, close, position and visibility operations. Swift assigns a stable model ID to each live HWND. Process ID and creation time are checked to protect against handle reuse.

The workspace tree and layout algorithms operate on `DesktopWindow` and `DesktopMonitor`. Tiles divide container space, accordion layouts reserve title strips, and floating windows retain independent geometry. Monitor work areas exclude taskbars. The native layer requests per-monitor DPI awareness and compensates for DWM frame borders when positioning windows.

A dedicated Windows message-loop thread hosts the tray icon and global hotkeys. WinEvent callbacks schedule debounced refresh work on the Swift main actor. Command and refresh sessions serialize model changes. Layout caches avoid sending the same position request repeatedly to applications with minimum-size constraints.

## Workspaces and recovery

Each monitor displays one AeroSpace workspace. Windows on inactive workspaces are hidden using Win32 visibility operations. The manager's workspaces do not map to Windows virtual desktops; windows from another Windows virtual desktop are excluded from discovery.

Before hiding a window, the native layer journals its identity to `%LOCALAPPDATA%\AeroSpace\hidden-<session>.bin` and marks ownership on the window. Restore operations verify HWND, process ID, process creation time and the ownership property. Disable and shutdown restore managed hidden windows. A watchdog waits for the application process to exit and restores journaled windows; startup also recovers stale entries. An exclusively opened user/session lock file prevents concurrent managers and coordinates recovery. Unlike a mutex, the handle can be closed from any Swift executor thread and is released when the process exits. Lock and journal files have an ACL restricted to the current user.

`ShowWindowAsync` queues visibility changes on the target UI thread. Recovery entries remain while their window/process/property identity matches, even after a show request, so a queued hide cannot outlive its recovery record. Destroyed or reused windows are pruned. This conservative policy means recovery may show a previously managed window that its own application subsequently hid. Foreground requests wait briefly for asynchronous show/restore completion and report rejection rather than claiming focus was granted.

## CLI protocol

The client and server communicate over a named pipe scoped to the current Windows user and session. The pipe ACL permits that user and rejects remote clients. Each JSON message has a little-endian 32-bit byte length, with a one MiB maximum frame.

The client parses arguments, sends the command and environment, and receives stdout, stderr and an exit code. The server parses the command again and executes it against the main-actor model. Pipe reading runs on worker threads; model mutations remain serialized. Foreground permission is passed from the invoking client when Windows permits it.

## Configuration and bindings

TOMLDecoder parses configuration into the existing Swift configuration model. Windows virtual-key codes and `RegisterHotKey` replace the macOS HotKey dependency. `alt`, `ctrl`, `shift` and `win` are the supported modifiers. Mode changes replace registered bindings, restoring previous registrations if the new set cannot be installed.

Reload first parses configuration and attempts hotkey registration, then commits the new model. Invalid configuration keeps the previous accepted configuration. Configuration callbacks use the command subsystem; `exec-and-forget` launches a detached PowerShell script through the native process bridge.
