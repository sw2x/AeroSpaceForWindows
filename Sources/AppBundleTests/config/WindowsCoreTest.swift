@testable import AppBundle
import Common
import Foundation
import WinSDK
import XCTest

@MainActor
final class WindowsCoreTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        resetHotKeys()
        activeMode = mainModeId
    }

    override func tearDown() async throws {
        resetHotKeys()
        activeMode = mainModeId
    }

    func testArgumentsRoundTripThroughWindowsParser() async {
        let arguments = ["", "plain", "two words", "日本語", "a\"b", "C:\\Program Files\\", "\\\\server\\share\\", "slashes\\\\\"quote"]
        let command = (["fixture.exe"] + arguments).map(quoteWindowsArgument).joined(separator: " ")
        let utf16 = Array(command.utf16) + [0]
        var count: Int32 = 0
        guard let parsed = utf16.withUnsafeBufferPointer({ CommandLineToArgvW($0.baseAddress, &count) }) else {
            XCTFail("CommandLineToArgvW failed")
            return
        }
        defer { _ = LocalFree(UnsafeMutableRawPointer(parsed)) }
        let values = (0..<Int(count)).map { index -> String in
            let value = parsed[index]!
            return String(decoding: UnsafeBufferPointer(start: value, count: Int(wcslen(value))), as: UTF16.self)
        }
        assertEquals(values, ["fixture.exe"] + arguments)
    }

    func testDuplicatePhysicalKeysPreservePreviousBindings() async {
        let old = HotkeyBinding(.option, .h, .cmd(FocusCommand.new(direction: .left)))
        assertNil(replaceHotkeys([old.descriptionWithKeyCode: old]))
        let previous = registeredBindings
        let enter = HotkeyBinding(.option, .return, .empty)
        let keypadEnter = HotkeyBinding(.option, .keypadEnter, .empty)
        assertNotNil(replaceHotkeys(["enter": enter, "keypad-enter": keypadEnter]))
        assertEquals(registeredBindings, previous)
    }

    func testUnsupportedKeyPreservesPreviousBindings() async {
        let old = HotkeyBinding(.option, .h, .empty)
        assertNil(replaceHotkeys(["old": old]))
        let previous = registeredBindings
        assertNotNil(replaceHotkeys(["unsupported": HotkeyBinding(.option, .function, .empty)]))
        assertEquals(registeredBindings, previous)
    }

    func testModeRegistrationFailurePreservesActiveMode() async {
        let enter = HotkeyBinding(.option, .return, .empty)
        let keypadEnter = HotkeyBinding(.option, .keypadEnter, .empty)
        config.modes["duplicate"] = Mode(bindings: ["enter": enter, "keypad-enter": keypadEnter])
        assertFalse(await activateMode_nonCancellable("duplicate"))
        assertEquals(activeMode, mainModeId)
        assertTrue(registeredBindings.isEmpty)
    }

    func testInvalidReloadPreservesConfigurationAndBindings() async throws {
        let old = HotkeyBinding(.option, .h, .empty)
        config.accordionPadding = 47
        assertNil(replaceHotkeys(["old": old]))
        let previous = registeredBindings
        let previousUrl = configUrl
        let temporary = projectRoot.appending(path: ".build/windows-core-\(UUID().uuidString).toml")
        try "config-version = 2\nunknown-windows-option = true\n".write(to: temporary, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let result = await reloadConfig_nonCancellable(forceConfigUrl: temporary)
        assertFalse(result.isOk)
        assertEquals(config.accordionPadding, 47)
        assertEquals(configUrl, previousUrl)
        assertEquals(registeredBindings, previous)
    }

    func testWindowsModifierAndRemovedMacOptions() async {
        let windows = parseConfig("config-version = 2\n[mode.main.binding]\nwin-shift-h = 'focus left'\n")
        assertEquals(windows.errors, [])
        assertEquals(windows.config.modes[mainModeId]?.bindings["win-shift-h"]?.modifiers, [.command, .shift])
        let oldModifier = parseConfig("config-version = 2\n[mode.main.binding]\ncmd-h = 'focus left'\n")
        assertFalse(oldModifier.errors.isEmpty)
        for key in ["start-at-login", "automatically-unhide-macos-hidden-apps", "focus-follows-mouse"] {
            assertFalse(parseConfig("config-version = 2\n\(key) = true\n").errors.isEmpty)
        }
    }

    func testWorkspaceMoveRelayoutsAcrossDifferentMonitorSizes() async throws {
        let primary = DesktopMonitor(nativeMonitorIndex: 1, name: "Primary",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1040), isMain: true)
        let left = DesktopMonitor(nativeMonitorIndex: 2, name: "Left",
            rect: Rect(topLeftX: -2560, topLeftY: -200, width: 2560, height: 1440),
            visibleRect: Rect(topLeftX: -2560, topLeftY: -200, width: 2560, height: 1400), isMain: false)
        monitorsForTests = [primary, left]
        defer {
            monitorsForTests = nil
            gcMonitors()
        }
        gcMonitors()
        config.gaps = .zero
        let workspace = Workspace.get(byName: "windows-multi-monitor")
        assertTrue(left.setActiveWorkspace(workspace))
        let first = TestWindow.new(id: 201, parent: workspace.rootTilingContainer)
        let second = TestWindow.new(id: 202, parent: workspace.rootTilingContainer)
        assertTrue(workspace.focusWorkspace())
        try await workspace.layoutWorkspace()
        assertFrame(first.lastAppliedLayoutPhysicalRect, Rect(topLeftX: -2560, topLeftY: -200, width: 1280, height: 1400))
        assertFrame(second.lastAppliedLayoutPhysicalRect, Rect(topLeftX: -1280, topLeftY: -200, width: 1280, height: 1400))

        let result = await parseCommand("move-workspace-to-monitor main").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertTrue(primary.activeWorkspace === workspace)
        assertFalse(left.activeWorkspace === workspace)
        try await workspace.layoutWorkspace()
        assertFrame(first.lastAppliedLayoutPhysicalRect, Rect(topLeftX: 0, topLeftY: 0, width: 960, height: 1040))
        assertFrame(second.lastAppliedLayoutPhysicalRect, Rect(topLeftX: 960, topLeftY: 0, width: 960, height: 1040))
    }

    func testReadOnlyShellBlocksModeChangesAndAllowsQueries() async {
        let previousReadOnly = serverArgs.isReadOnly
        let previousEnabled = TrayMenuModel.shared.isEnabled
        defer {
            serverArgs.isReadOnly = previousReadOnly
            TrayMenuModel.shared.isEnabled = previousEnabled
        }
        let binding = HotkeyBinding(.option, .h, .empty)
        config.modes[mainModeId] = Mode(bindings: [binding.descriptionWithKeyCode: binding])
        serverArgs.isReadOnly = true
        TrayMenuModel.shared.isEnabled = false
        let rejected = await parseCommand("mode main").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(rejected.exitCode.rawValue, 2)
        assertTrue(registeredBindings.isEmpty)
        let query = await parseCommand("list-workspaces --all --count").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(query.exitCode.rawValue, 0)
        assertTrue((query.stdout.singleOrNil().flatMap(Int.init) ?? 0) > 0)
    }
}

private func assertFrame(_ actual: Rect?, _ expected: Rect, file: StaticString = #filePath, line: UInt = #line) {
    assertEquals(actual?.topLeftCorner, expected.topLeftCorner, file: file, line: line)
    assertEquals(actual?.size, expected.size, file: file, line: line)
}
