import Darwin
import Foundation

/// The prototype stores only generated, fictional records. A real backup adapter
/// would be a separate future implementation with separately reviewed consent,
/// encryption and credential handling. This protocol supplies none of those.
@MainActor
public protocol DeviceStorage: AnyObject {
    func loadJobs() throws -> [SyncJob]
    func saveJobs(_ jobs: [SyncJob]) throws
    func loadRecords(for device: DemoDeviceKey) throws -> DeviceRecords
    func saveRecords(_ records: DeviceRecords, fixture: DemoFixture) throws
}

/// Plaintext local demo storage. An advisory process lock prevents cooperating
/// DeviceBridge executables from writing the same store concurrently.
@MainActor
public final class FileDeviceStorage: DeviceStorage {
    public let rootURL: URL
    private let rootDescriptor: Int32
    private let lockDescriptor: Int32
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private static let maximumStoreBytes = 4 * 1024 * 1024

    private struct Catalog: Codable {
        let schemaVersion: Int
        let syntheticDemo: Bool
        let jobs: [SyncJob]
    }

    private struct Snapshot: Codable {
        let schemaVersion: Int
        let syntheticDemo: Bool
        let fixture: DemoFixture
        let records: DeviceRecords
    }

    public init(rootURL: URL) throws {
        self.rootURL = rootURL.standardizedFileURL
        try Self.prepareDirectory(self.rootURL)
        // Pin the directory for this storage lifetime. Later path replacement
        // must not redirect I/O away from the directory whose lock we hold.
        let directory = Darwin.open(self.rootURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw Self.posixError("Open demo store directory") }
        let descriptor = Darwin.openat(directory, ".writer.lock",
                                       O_CREAT | O_RDWR | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            let error = Self.posixError("Open demo store lock")
            Darwin.close(directory)
            throw error
        }
        do {
            var info = stat()
            guard Darwin.fstat(descriptor, &info) == 0 else { throw Self.posixError("Inspect demo store lock") }
            guard (info.st_mode & S_IFMT) == S_IFREG else {
                throw DeviceBridgeError.invalidStore("Demo store lock must be a regular file.")
            }
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw DeviceBridgeError.storeInUse }
            // Only the locked writer may remove files abandoned before rename.
            try Self.removeAbandonedWrites(in: directory)
        } catch {
            Darwin.close(descriptor)
            Darwin.close(directory)
            throw error
        }
        self.rootDescriptor = directory
        self.lockDescriptor = descriptor
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    deinit {
        _ = flock(lockDescriptor, LOCK_UN)
        Darwin.close(lockDescriptor)
        Darwin.close(rootDescriptor)
    }

    public func loadJobs() throws -> [SyncJob] {
        guard let data = try readBounded("queue.json", in: rootDescriptor) else { return [] }
        let catalog = try decoder.decode(Catalog.self, from: data)
        guard catalog.schemaVersion == 1, catalog.syntheticDemo else {
            throw DeviceBridgeError.invalidStore("Unsupported queue catalog.")
        }
        try Self.validateJobs(catalog.jobs)
        return catalog.jobs
    }

    public func saveJobs(_ jobs: [SyncJob]) throws {
        try Self.validateJobs(jobs)
        let data = try encoder.encode(Catalog(schemaVersion: 1, syntheticDemo: true, jobs: jobs))
        try atomicWrite(data, named: "queue.json", in: rootDescriptor)
    }

    public func loadRecords(for device: DemoDeviceKey) throws -> DeviceRecords {
        guard let directory = try recordsDirectory(for: device, create: false) else { return DeviceRecords() }
        defer { Darwin.close(directory) }
        guard let data = try readBounded("records.json", in: directory) else { return DeviceRecords() }
        let snapshot = try decoder.decode(Snapshot.self, from: data)
        guard snapshot.schemaVersion == 1, snapshot.syntheticDemo, snapshot.fixture.device == device else {
            throw DeviceBridgeError.invalidStore("Device snapshot identity does not match its isolated directory.")
        }
        try Self.validateRecords(snapshot.records, fixture: snapshot.fixture)
        return snapshot.records
    }

    public func saveRecords(_ records: DeviceRecords, fixture: DemoFixture) throws {
        try Self.validateRecords(records, fixture: fixture)
        guard let directory = try recordsDirectory(for: fixture.device, create: true) else {
            throw DeviceBridgeError.invalidStore("Device snapshot directory is missing.")
        }
        defer { Darwin.close(directory) }
        let snapshot = Snapshot(schemaVersion: 1, syntheticDemo: true, fixture: fixture, records: records)
        try atomicWrite(try encoder.encode(snapshot), named: "records.json", in: directory)
    }

    public func recordsURL(for device: DemoDeviceKey) -> URL {
        rootURL.appendingPathComponent("devices", isDirectory: true)
            .appendingPathComponent(device.id.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent("records.json")
    }

    private static func validateJobs(_ jobs: [SyncJob]) throws {
        guard jobs.count <= 1_000,
              Set(jobs.map(\.id)).count == jobs.count,
              jobs.allSatisfy({ $0.progress.isFinite && (0...1).contains($0.progress)
                  && (1...1_000).contains($0.attempt) && $0.detail.utf8.count <= 512 }) else {
            throw DeviceBridgeError.invalidStore("Queue catalog failed validation.")
        }
    }

    private static func validateRecords(_ records: DeviceRecords, fixture: DemoFixture) throws {
        guard let updatedAt = records.updatedAt, updatedAt.timeIntervalSince1970.isFinite,
              records == fixture.records(updatedAt: updatedAt) else {
            throw DeviceBridgeError.invalidStore("Only unchanged built-in fictional records can be stored or displayed.")
        }
    }

    private func readBounded(_ name: String, in directory: Int32) throws -> Data? {
        let descriptor = Darwin.openat(directory, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            throw Self.posixError("Open store file")
        }
        defer { Darwin.close(descriptor) }
        return try BoundedFileReader.read(descriptor: descriptor, maximumBytes: Self.maximumStoreBytes, label: "Store file")
    }

    private func recordsDirectory(for device: DemoDeviceKey, create: Bool) throws -> Int32? {
        guard let devices = try Self.openDirectory("devices", in: rootDescriptor, create: create) else { return nil }
        defer { Darwin.close(devices) }
        return try Self.openDirectory(device.id.uuidString.lowercased(), in: devices, create: create)
    }

    /// Each name is one fixed path component, never a slash-separated path.
    private static func openDirectory(_ name: String, in parent: Int32, create: Bool) throws -> Int32? {
        if create, Darwin.mkdirat(parent, name, S_IRWXU) != 0, errno != EEXIST {
            throw posixError("Create demo state directory")
        }
        let descriptor = Darwin.openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            if !create, errno == ENOENT { return nil }
            throw posixError("Open demo state directory")
        }
        return descriptor
    }

    private static func prepareDirectory(_ url: URL) throws {
        try rejectSymlink(url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
    }

    private static func rejectSymlink(_ url: URL) throws {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return }
        guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else {
            throw DeviceBridgeError.invalidStore("Symbolic links are not supported for demo state files or directories.")
        }
    }

    private func atomicWrite(_ data: Data, named name: String, in directory: Int32) throws {
        guard data.count <= Self.maximumStoreBytes else {
            throw DeviceBridgeError.invalidStore("Store file exceeds the 4 MiB prototype limit.")
        }
        var info = stat()
        if Darwin.fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == 0 {
            guard (info.st_mode & S_IFMT) != S_IFLNK else {
                throw DeviceBridgeError.invalidStore("Symbolic links are not supported for demo state files or directories.")
            }
        } else if errno != ENOENT {
            throw Self.posixError("Inspect demo state file")
        }
        let temporary = ".\(UUID().uuidString).tmp"
        let descriptor = Darwin.openat(directory, temporary,
                                       O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw Self.posixError("Create atomic demo state file") }
        defer {
            Darwin.close(descriptor)
            Darwin.unlinkat(directory, temporary, 0)
        }
        try data.withUnsafeBytes { buffer in
            guard let address = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(descriptor, address.advanced(by: offset), buffer.count - offset)
                if written < 0 && errno == EINTR { continue }
                guard written > 0 else { throw Self.posixError("Write demo state") }
                offset += written
            }
        }
        guard Darwin.fsync(descriptor) == 0 else { throw Self.posixError("Flush demo state") }
        guard Darwin.renameat(directory, temporary, directory, name) == 0 else { throw Self.posixError("Commit demo state") }
        // The new file is now committed. Directory flush is best effort because
        // filesystem support differs; this is not a hardware power-loss guarantee.
        _ = Darwin.fsync(directory)
    }

    private static func removeAbandonedWrites(in root: Int32) throws {
        try removeTemporaryFiles(in: root)
        guard let devices = try openDirectory("devices", in: root, create: false) else { return }
        defer { Darwin.close(devices) }
        for device in DemoDeviceKey.allCases {
            if let directory = try openDirectory(device.id.uuidString.lowercased(), in: devices, create: false) {
                defer { Darwin.close(directory) }
                try removeTemporaryFiles(in: directory)
            }
        }
    }

    private static func removeTemporaryFiles(in directory: Int32) throws {
        // A separate directory stream leaves the retained descriptor's offset alone.
        let descriptor = Darwin.openat(directory, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw posixError("Open demo temporary-file directory") }
        guard let stream = fdopendir(descriptor) else {
            let error = posixError("Inspect demo temporary-file directory")
            Darwin.close(descriptor)
            throw error
        }
        defer { closedir(stream) }
        while true {
            errno = 0
            guard let entry = readdir(stream) else {
                if errno != 0 { throw posixError("List demo temporary files") }
                break
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            // Match only the exact names produced by atomicWrite, in known store
            // directories. Never recurse into arbitrary folders or follow links.
            guard name.count == 41, name.hasPrefix("."), name.hasSuffix(".tmp"),
                  let id = UUID(uuidString: String(name.dropFirst().dropLast(4))),
                  name == ".\(id.uuidString).tmp" else { continue }
            var info = stat()
            guard Darwin.fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
                if errno == ENOENT { continue }
                throw posixError("Inspect abandoned demo write")
            }
            guard (info.st_mode & S_IFMT) == S_IFREG else { continue }
            guard Darwin.unlinkat(directory, name, 0) == 0 else {
                if errno == ENOENT { continue }
                throw posixError("Remove abandoned demo write")
            }
        }
    }

    private static func posixError(_ operation: String) -> NSError {
        let code = errno
        return NSError(domain: NSPOSIXErrorDomain, code: Int(code),
                       userInfo: [NSLocalizedDescriptionKey: "\(operation): \(String(cString: strerror(code)))"])
    }
}
