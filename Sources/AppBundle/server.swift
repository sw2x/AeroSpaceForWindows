import Foundation
import Common
import NativeWindows

func startPipeServer() {
    Thread.detachNewThread {
        while true {
            let handle = aw_pipe_listen()
            guard handle != 0 else { eprint("Can't create AeroSpace pipe: \(aw_last_error())"); return }
            if aw_pipe_accept(handle) == 0 { aw_pipe_close(handle); continue }
            let connection = PipeConnection(handle: handle)
            Thread.detachNewThread {
                guard let data = connection.read() else { return }
                Task { @MainActor in
                    let response = await processRequest(data)
                    connection.write(response)
                }
            }
        }
    }
}

@MainActor private func processRequest(_ data: Data) async -> ServerAnswer {
    let version = "\(aeroSpaceAppVersion) \(gitHash)"
    guard let request = try? JSONDecoder().decode(ClientRequest.self, from: data) else {
        return ServerAnswer(exitCode: 2, stderr: "Invalid JSON request", serverVersionAndHash: version)
    }
    let parsed = parseCommand(request.args)
    switch parsed {
        case .help(let help): return ServerAnswer(exitCode: 0, stdout: help, serverVersionAndHash: version)
        case .failure(let error): return ServerAnswer(exitCode: error.exitCode, stderr: error.msg, serverVersionAndHash: version)
        case .cmd(let command):
            guard let token = RunSessionGuard.isServerEnabled(orIsEnableCommand: command) else {
                let error = serverArgs.isReadOnly ? "AeroSpace was started with --read-only" : "AeroSpace is disabled; use 'aerospace enable on'"
                return ServerAnswer(exitCode: 2, stderr: error, serverVersionAndHash: version)
            }
            do {
                let result = try await runLightSession(.socketServer(command.args), token) {
                    await command.run(CmdEnv(windowId: request.windowId.flattenOptional(), workspaceName: request.workspace.flattenOptional()), CmdStdin(request.stdin))
                }
                return ServerAnswer(exitCode: result.exitCode.rawValue, stdout: result.stdout.joined(separator: "\n"),
                                    stderr: result.stderr.joined(separator: "\n"), serverVersionAndHash: version)
            } catch {
                return ServerAnswer(exitCode: command.args.failExitCode, stderr: "\(error)", serverVersionAndHash: version)
            }
    }
}
