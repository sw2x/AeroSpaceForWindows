import Foundation
import Common

@main struct Main {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        let usage = """
        USAGE: aerospace [-h|--help] [-v|--version] <command> [<args>...]

        COMMANDS:
        \(CmdKind.allCases.map(\.rawValue).sorted().joined(separator: "\n"))
        """
        if args.isEmpty { Common.exit(2, err: usage) }
        if args == ["--help"] || args == ["-h"] { Common.exit(0, out: usage) }
        if args == ["--version"] || args == ["-v"] {
            Common.exit(0, out: "AeroSpace for Windows \(aeroSpaceAppVersion) \(gitHash)")
        }
        let parsed: any CmdArgs
        switch parseCmdArgs(args.slice) {
            case .cmd(let command): parsed = command
            case .help(let help): Common.exit(0, out: help)
            case .failure(let error): Common.exit(error.exitCode, err: error.msg)
        }
        if parsed is TrueCmdArgs { Common.exit(0) }
        if parsed is FalseCmdArgs { Common.exit(1) }
        var stdin = ""
        if parsed.commonState.explicitStdinFlag == true {
            while let line = readLine(strippingNewline: false) {
                stdin += line
                if stdin.utf8.count > 512 * 1024 { Common.exit(2, err: "stdin exceeds 512 KiB") }
            }
        }
        guard let connection = PipeConnection.connect() else {
            Common.exit(parsed.failExitCode, err: "Can't connect to AeroSpace. Start AeroSpaceApp.exe first.")
        }
        let request = ClientRequest(args: args, stdin: stdin,
            windowId: ProcessInfo.processInfo.environment[AEROSPACE_WINDOW_ID].flatMap(UInt32.init),
            workspace: ProcessInfo.processInfo.environment[AEROSPACE_WORKSPACE])
        guard connection.write(request), let data = connection.read(),
              let response = try? JSONDecoder().decode(ServerAnswer.self, from: data) else {
            Common.exit(parsed.failExitCode, err: "Invalid or interrupted response from AeroSpace")
        }
        if !response.stdout.isEmpty { print(response.stdout) }
        if !response.stderr.isEmpty { eprint(response.stderr) }
        Common.exit(response.exitCode)
    }
}
