import Foundation
import NativeWindows

public final class PipeConnection: @unchecked Sendable {
    public let handle: UInt64
    public init(handle: UInt64) { self.handle = handle }
    deinit { aw_pipe_close(handle) }
    public static func connect() -> PipeConnection? {
        let handle = aw_pipe_connect(3000)
        guard handle != 0 else { return nil }
        aw_allow_server_foreground(handle)
        return PipeConnection(handle: handle)
    }
    public func read() -> Data? {
        var pointer: UnsafeMutablePointer<CChar>?
        var size: UInt32 = 0
        guard aw_pipe_read(handle, &pointer, &size) != 0, let pointer else { return nil }
        defer { aw_free(pointer) }
        return Data(bytes: pointer, count: Int(size))
    }
    @discardableResult public func write<T: Encodable>(_ value: T) -> Bool {
        guard let data = try? JSONEncoder.aeroSpaceDefault.encode(value) else { return false }
        return data.withUnsafeBytes { bytes in
            aw_pipe_write(handle, bytes.baseAddress?.assumingMemoryBound(to: CChar.self), UInt32(bytes.count)) != 0
        }
    }
}
