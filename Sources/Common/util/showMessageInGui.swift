import Foundation
import NativeWindows

func showMessageInGui(filenameIfConsoleApp: String, title: String, message: String) {
    eprint("\(title)\n\(message)")
    // Recovery runs synchronously before reporting; no modal dialog during fatal errors.
    let directory = FileManager.default.temporaryDirectory.appending(path: "AeroSpace")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try? message.write(to: directory.appending(path: filenameIfConsoleApp), atomically: true, encoding: .utf8)
}
