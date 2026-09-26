import Foundation
import Common
import NativeWindows

@MainActor var activeMode: String? = mainModeId
@MainActor var registeredBindings: [Int32: HotkeyBinding] = [:]

@MainActor func resetHotKeys() {
    if !isUnitTest { for id in registeredBindings.keys { aw_unregister_hotkey(id) } }
    registeredBindings = [:]
}

@MainActor func replaceHotkeys(_ bindings: [String: HotkeyBinding]) -> String? {
    let previous = registeredBindings
    resetHotKeys()
    var physicalKeys = Set<UInt64>()
    var next: Int32 = 1
    for binding in bindings.values.sorted(by: { $0.descriptionWithKeyNotation < $1.descriptionWithKeyNotation }) {
        guard let vk = binding.keyCode.virtualKey,
              physicalKeys.insert((UInt64(binding.modifiers.rawValue) << 32) | UInt64(vk)).inserted,
              isUnitTest || aw_register_hotkey(next, binding.modifiers.rawValue, vk) != 0 else {
            resetHotKeys()
            for (id, value) in previous {
                if let key = value.keyCode.virtualKey, isUnitTest || aw_register_hotkey(id, value.modifiers.rawValue, key) != 0 { registeredBindings[id] = value }
            }
            return "Can't register binding '\(binding.descriptionWithKeyNotation)': unsupported key, duplicate physical key, or another application/Windows owns the shortcut"
        }
        registeredBindings[next] = binding
        next += 1
    }
    return nil
}

@MainActor @discardableResult func activateMode_nonCancellable(_ targetMode: String?) async -> Bool {
    if let targetMode, config.modes[targetMode] == nil { return false }
    let bindings = targetMode.flatMap { config.modes[$0] }?.bindings ?? [:]
    if let error = replaceHotkeys(bindings) { eprint(error); return false }
    let old = activeMode
    activeMode = targetMode
    if old != targetMode { _ = await config.onModeChanged.run(.defaultEnv, .emptyStdin) }
    return true
}

struct HotkeyBinding: Equatable, Sendable {
    let modifiers: KeyModifiers
    let keyCode: Key
    let commands: Shell<any Command>
    let descriptionWithKeyCode: String
    let descriptionWithKeyNotation: String
    init(_ modifiers: KeyModifiers, _ keyCode: Key, _ commands: Shell<any Command>, descriptionWithKeyNotation: String) {
        self.modifiers = modifiers; self.keyCode = keyCode; self.commands = commands
        self.descriptionWithKeyNotation = descriptionWithKeyNotation
        descriptionWithKeyCode = modifiers.isEmpty ? keyCode.toString() : modifiers.toString() + "-" + keyCode.toString()
    }
    static func == (a: Self, b: Self) -> Bool {
        a.modifiers == b.modifiers && a.keyCode == b.keyCode && a.commands.strictEquals(b.commands)
    }
}

func parseBindings(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext, _ mapping: [String: Key]) -> [String: HotkeyBinding] {
    guard let table = raw.asDictOrNil else { c.errors.append(expectedActualTypeDiagnostic(expected: .table, actual: raw.tomlType, backtrace)); return [:] }
    var result: [String: HotkeyBinding] = [:]
    for (notation, rawCommand) in table {
        let trace = backtrace + .key(notation)
        guard let (modifiers, key) = parseBinding(notation, trace, mapping).getOrNil(appendErrorTo: &c.errors) else { continue }
        let commands = parseShellOfCommandsForConfig(rawCommand, trace, &c)
        let binding = HotkeyBinding(modifiers, key, commands, descriptionWithKeyNotation: notation)
        if result[binding.descriptionWithKeyCode] != nil { c.errors.append(.init(trace, "'\(binding.descriptionWithKeyCode)' Binding redeclaration")) }
        result[binding.descriptionWithKeyCode] = binding
    }
    return result
}

func parseBinding(_ raw: String, _ trace: ConfigBacktrace, _ mapping: [String: Key]) -> ResOrConfigParseDiagnostic<(KeyModifiers, Key)> {
    let parts = raw.split(separator: "-")
    var modifiers = KeyModifiers()
    for part in parts.dropLast() {
        guard let modifier = modifiersMap[String(part)] else { return .failure(.init(trace, "Can't parse modifiers in '\(raw)' binding")) }
        modifiers.insert(modifier)
    }
    guard let name = parts.last, let key = mapping[String(name)], key.virtualKey != nil else { return .failure(.init(trace, "Can't parse the key in '\(raw)' binding")) }
    return .success((modifiers, key))
}
