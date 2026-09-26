import Foundation
import Common

@MainActor private var watcher: Task<Void, Never>?
@MainActor func syncConfigFileWatcher() {
    watcher?.cancel()
    guard config.autoReloadConfig else { watcher = nil; return }
    let url = configUrl
    watcher = Task { @MainActor in
        var previous = try? Data(contentsOf: url)
        while !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(500)) } catch { break }
            guard let current = try? Data(contentsOf: url), current != previous else { continue }
            previous = current
            let result = await reloadConfig_nonCancellable()
            if !result.isOk { eprint(result.stdout + result.stderr) }
            if result.isOk { break } // A successful reload installs the replacement watcher.
        }
    }
}
