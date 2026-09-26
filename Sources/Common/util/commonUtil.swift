import Foundation
import NativeWindows

public let mainModeId = "main"

@TaskLocal
public var refreshSessionEvent: RefreshSessionEvent? = nil

@TaskLocal
private var recursionDetectorDuringTermination = false

public func bugPrompt(
    _ __message: String = "",
    isDie: Bool = false,
    file: StaticString = #fileID,
    line: Int = #line,
    column: Int = #column,
    function: String = #function,
) -> String {
    let _message = __message.contains("\n") ? "\n" + __message.prefixLines(with: "    ") : __message
    let thread = Thread.current
    return """
        Please include this diagnostic when reporting a Windows port issue.
        Describe what you did to trigger this error.

        Message: \(_message)
        Version: \(aeroSpaceAppVersion)
        Git hash: \(gitHash)
        refreshSessionEvent: \(refreshSessionEvent.prettyDescription)
        Date: \(Date.now)
        Thread name: \(thread.name.prettyDescription)
        Is main thread: \(thread.isMainThread)
        Windows version: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Coordinate: \(file):\(line):\(column) \(function)
        recursionDetectorDuringTermination: \(recursionDetectorDuringTermination)
        cli: \(isCli)
        die: \(isDie)

        Stacktrace:
        \(getStringStacktrace())
        """
}

public func dieT<T>(
    _ __message: String = "",
    file: StaticString = #fileID,
    line: Int = #line,
    column: Int = #column,
    function: String = #function,
) -> T {
    let message = bugPrompt(__message, isDie: true, file: file, line: line, column: column, function: function)
    if !isUnitTest && isServer {
        showMessageInGui(
            filenameIfConsoleApp: recursionDetectorDuringTermination
                ? "aerospace-runtime-error-recursion.txt"
                : "aerospace-runtime-error.txt",
            title: "AeroSpace Runtime Error",
            message: message,
        )
    }
    if let terminationHandler, !recursionDetectorDuringTermination {
        $recursionDetectorDuringTermination.withValue(true) {
            terminationHandler.beforeTermination()
        }
    }
    fatalError("\n" + message)
}


public enum RefreshSessionEvent: Sendable, CustomStringConvertible {
    case configAutoReload
    case globalObserver(String)
    case globalObserverLeftMouseUp
    case menuBarButton
    case hotkeyBinding
    case startup
    case socketServer(any CmdArgs)
    case resetManipulatedWithMouse
    case ax(String)
    case focusFollowsMouse

    public var isStartup: Bool {
        if case .startup = self { return true } else { return false }
    }

    public var isFocusFollowsMouse: Bool {
        if case .focusFollowsMouse = self { return true } else { return false }
    }

    public var description: String {
        switch self {
            case .ax(let str): "ax(\(str))"
            case .configAutoReload: "configAutoReload"
            case .globalObserver(let str): "globalObserver(\(str))"
            case .globalObserverLeftMouseUp: "globalObserverLeftMouseUp"
            case .hotkeyBinding: "hotkeyBinding"
            case .menuBarButton: "menuBarButton"
            case .resetManipulatedWithMouse: "resetManipulatedWithMouse"
            case .socketServer(let args): "socketServer: \(args)"
            case .startup: "startup"
            case .focusFollowsMouse: "focusFollowsMouse"
        }
    }
}

// periphery:ignore
public func throwT<T, E: Error>(_ error: E) throws(E) -> T { throw error }

public func getStringStacktrace() -> String { "" }

@inlinable public func die(
    _ message: String = "",
    file: StaticString = #fileID,
    line: Int = #line,
    column: Int = #column,
    function: String = #function,
) -> Never {
    dieT(message, file: file, line: line, column: column, function: function)
}

public func check(
    _ condition: Bool,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #fileID,
    line: Int = #line,
    column: Int = #column,
    function: String = #function,
) {
    if !condition {
        die(message(), file: file, line: line, column: column, function: function)
    }
}

nonisolated(unsafe) public var isUnitTest: Bool = false

extension CaseIterable where Self: RawRepresentable, RawValue == String {
    public static var cliArgsCases: [String] { allCases.map(\.rawValue) }
    public static var unionLiteral: String { cliArgsCases.joinedCliArgs }
}

extension [String] {
    public var joinedCliArgs: String { "(" + self.joined(separator: "|") + ")" }
}

extension Int {
    public func toDouble() -> Double { Double(self) }
}

public func + <K, V>(lhs: [K: V], rhs: [K: V]) -> [K: V] {
    lhs.merging(rhs) { _, r in r }
}

extension String {
    public func removePrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }

    public func prependLines(_ prefix: String) -> String {
        split(separator: "\n").map { prefix + $0 }.joined(separator: "\n")
    }
}

extension Bool {
    /// Implication
    /// | a     | b     | a.implies(b) |
    /// |-------|-------|--------------|
    /// | false | false | true         |
    /// | false | true  | true         |
    /// | true  | false | false        |
    /// | true  | true  | true         |
    public func implies(_ mustHold: @autoclosure () -> Bool) -> Bool { !self || mustHold() }
}

extension URL { public func open(with url: URL) { aw_open_file(path) } }

public func eprint(_ msg: String) {
    aw_stderr(msg + "\n")
}

public func exit(_ exitCode: Int32, out: String? = nil, err: String? = nil) -> Never {
    exitT(exitCode, out: out, err: err)
}

public func exitT<T>(_ exitCode: Int32, out: String? = nil, err: String? = nil) -> T {
    if let out { print(out) }
    if let err { eprint(err) }
    aw_exit(exitCode)
    fatalError("Unreachable")
}

/// 'id' stands for 'identity'. It's a common name in functional programming
public func id<T>(_ t: T) -> T { t }

@inlinable public func zipIfCountsAreEqual<C1, C2>(_ c1: C1, _ c2: C2) -> Zip2Sequence<C1, C2>? where C1: Collection, C2: Collection {
    switch c1.count == c2.count {
        case true: zip(c1, c2)
        case false: nil
    }
}
