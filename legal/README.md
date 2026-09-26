# License notices

AeroSpace is distributed under the [MIT license](LICENSE.txt). The original Nikita Bobko copyright and attribution are retained in this Windows port.

## Current dependencies

- **TOMLDecoder** parses TOML. See [MIT license](third-party-license/LICENSE-TOMLDecoder.txt).
- **swift-collections** provides ordered collections. See [Apache 2.0 license](third-party-license/LICENSE-swift-collections.txt).
- **Swift runtime** libraries are copied beside the executables for ZIP distribution. See the [Swift license](third-party-license/LICENSE-Swift.txt), [Foundation license](third-party-license/LICENSE-Foundation.txt), [libdispatch license](third-party-license/LICENSE-libdispatch.txt), [BlocksRuntime license](third-party-license/LICENSE-BlocksRuntime.txt), [FoundationICU license](third-party-license/LICENSE-FoundationICU.txt) and [ICU notices](third-party-license/LICENSE-ICU.txt), retrieved from their official source repositories.
- **Microsoft Visual C++ runtime** DLLs are included from the Visual Studio redistributable directory by the packaging script.

## Historical notices

The original repository used HotKey for macOS hotkeys, ISSoundAdditions for audio controls and tomlplusplus in older TOML parsing code. These dependencies are not linked by the Windows package. Their license files remain in `third-party-license` to preserve the repository's historical notices.
