import Foundation
import AppBundle
import Common
import NativeWindows

@main struct Main {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.count == 2, args[0] == "--watchdog", let parent = UInt32(args[1]) { Common.exit(aw_watchdog(parent)) }
        if args.contains("--help") || args.contains("-h") {
            Common.exit(0, out: "USAGE: AeroSpaceApp.exe [--config-path <path>] [--read-only] [--manage-process <pid>]")
        }
        if args == ["--version"] || args == ["-v"] { Common.exit(0, out: "AeroSpace for Windows \(aeroSpaceAppVersion)") }
        guard aw_initialize() != 0 else { Common.exit(2, err: "AeroSpace is already running, or initialization failed") }
        await initAppBundle(args: args)
    }
}
