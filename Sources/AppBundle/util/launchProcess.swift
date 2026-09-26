import Foundation
import Common
import NativeWindows

func quoteWindowsArgument(_ value: String) -> String {
    var result = "\""
    var slashes = 0
    for character in value {
        if character == "\\" { slashes += 1; continue }
        if character == "\"" { result += String(repeating: "\\", count: slashes * 2 + 1) + "\"" }
        else { result += String(repeating: "\\", count: slashes) + String(character) }
        slashes = 0
    }
    return result + String(repeating: "\\", count: slashes * 2) + "\""
}

func launchProcess(executable: String, arguments: [String], environment: [String: String]) -> Bool {
    var normalized: [String: (String, String)] = [:]
    for (key, value) in environment { normalized[key.uppercased()] = (key, value) }
    var block: [UInt16] = []
    for (_, pair) in normalized.sorted(by: { $0.key < $1.key }) {
        guard !pair.0.contains("="), !pair.0.contains("\0"), !pair.1.contains("\0") else { return false }
        block += Array("\(pair.0)=\(pair.1)".utf16) + [0]
    }
    if block.isEmpty { block.append(0) }
    block.append(0)
    let command = ([executable] + arguments).map(quoteWindowsArgument).joined(separator: " ")
    return block.withUnsafeBufferPointer { aw_spawn(executable, command, $0.baseAddress) != 0 }
}

func launchPowerShell(_ script: String, environment: [String: String]) -> Bool {
    let system = ProcessInfo.processInfo.environment["SystemRoot"] ?? "C:\\Windows"
    let executable = system + "\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"
    let encoded = script.data(using: .utf16LittleEndian)!.base64EncodedString()
    return launchProcess(executable: executable, arguments: ["-NoProfile", "-NonInteractive", "-EncodedCommand", encoded], environment: environment)
}
