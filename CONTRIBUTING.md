# Contributing to the Windows port

This repository targets Windows 11 x64. Report Windows-specific problems in this repository, including the AeroSpace version, Windows version, configuration, reproduction steps, and affected application names. `aerospace list-windows --all --json` and `aerospace list-monitors --json` can help describe the environment; remove private window titles and paths before sharing output.

Use [development.md](dev-docs/development.md) to build and run tests. Keep Win32 calls in `Sources/NativeWindows` and platform-independent layout rules in the Swift model. Update command help and documentation when changing commands or configuration.

By contributing, you agree to distribute your changes under the [MIT license](LICENSE.txt). Preserve the original AeroSpace and dependency copyright notices. Upstream macOS issue trackers and documentation describe a separate project.
