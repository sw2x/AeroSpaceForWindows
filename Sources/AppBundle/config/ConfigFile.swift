import Common
import Foundation

func findCustomConfigUrl() -> ConfigFile {
    if let path = serverArgs.configLocation { return .file(URL(filePath: path)) }
    let environment = ProcessInfo.processInfo.environment
    let homeDirectory = (environment["HOME"] ?? environment["USERPROFILE"]).map { URL(filePath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser
    let home = homeDirectory.appending(path: ".aerospace.toml")
    let roaming = ProcessInfo.processInfo.environment["APPDATA"].map { URL(filePath: $0).appending(path: "AeroSpace/aerospace.toml") }
    if FileManager.default.fileExists(atPath: home.path) { return .file(home) }
    if let roaming, FileManager.default.fileExists(atPath: roaming.path) { return .file(roaming) }
    return .noCustomConfigExists
}
enum ConfigFile {
    case file(URL), ambiguousConfigError([URL]), noCustomConfigExists
    var urlOrNil: URL? { if case .file(let url) = self { return url }; return nil }
}
