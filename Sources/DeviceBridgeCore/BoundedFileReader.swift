import Darwin
import Foundation

/// Reject devices, pipes and symlinks before reading, without blocking on a FIFO.
/// Bound reads as well as stat size so growth during the read cannot evade the cap.
enum BoundedFileReader {
    static func read(_ url: URL, maximumBytes: Int, label: String) throws -> Data {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
        guard descriptor >= 0 else { throw posixError("Open \(label.lowercased())") }
        defer { Darwin.close(descriptor) }
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0 else { throw posixError("Inspect \(label.lowercased())") }
        guard (info.st_mode & S_IFMT) == S_IFREG else {
            throw ReadError("\(label) must be a regular file; pipes and devices are not supported.")
        }
        guard info.st_size >= 0, info.st_size <= maximumBytes else {
            throw ReadError("\(label) exceeds its \(maximumBytes)-byte size limit.")
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: min(16_384, maximumBytes + 1))
        while data.count <= maximumBytes {
            let capacity = min(buffer.count, maximumBytes + 1 - data.count)
            let count = buffer.withUnsafeMutableBytes { raw in
                Darwin.read(descriptor, raw.baseAddress, capacity)
            }
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw posixError("Read \(label.lowercased())") }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard data.count <= maximumBytes else {
            throw ReadError("\(label) exceeds its \(maximumBytes)-byte size limit.")
        }
        return data
    }

    private struct ReadError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    private static func posixError(_ operation: String) -> NSError {
        let code = errno
        return NSError(domain: NSPOSIXErrorDomain, code: Int(code),
                       userInfo: [NSLocalizedDescriptionKey: "\(operation): \(String(cString: strerror(code)))"])
    }
}
