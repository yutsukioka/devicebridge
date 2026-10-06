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
        let lockURL = self.rootURL.appendingPathComponent(".writer.lock")
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw Self.posixError("Open demo store lock") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(descriptor)
            throw DeviceBridgeError.storeInUse
        }
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
    }

    public func loadJobs() throws -> [SyncJob] {
        let url = rootURL.appendingPathComponent("queue.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let catalog = try decoder.decode(Catalog.self, from: readBounded(url))
        guard catalog.schemaVersion == 1, catalog.syntheticDemo else {
            throw DeviceBridgeError.invalidStore("Unsupported queue catalog.")
        }
        try Self.validateJobs(catalog.jobs)
        return catalog.jobs
    }

    public func saveJobs(_ jobs: [SyncJob]) throws {
        try Self.validateJobs(jobs)
        let data = try encoder.encode(Catalog(schemaVersion: 1, syntheticDemo: true, jobs: jobs))
        try atomicWrite(data, to: rootURL.appendingPathComponent("queue.json"))
    }

    public func loadRecords(for device: DemoDeviceKey) throws -> DeviceRecords {
        let url = recordsURL(for: device)
        guard FileManager.default.fileExists(atPath: url.path) else { return DeviceRecords() }
        let snapshot = try decoder.decode(Snapshot.self, from: readBounded(url))
        guard snapshot.schemaVersion == 1, snapshot.syntheticDemo, snapshot.fixture.device == device else {
            throw DeviceBridgeError.invalidStore("Device snapshot identity does not match its isolated directory.")
        }
        try Self.validateRecords(snapshot.records, fixture: snapshot.fixture)
        return snapshot.records
    }

    public func saveRecords(_ records: DeviceRecords, fixture: DemoFixture) throws {
        try Self.validateRecords(records, fixture: fixture)
        let url = recordsURL(for: fixture.device)
        try Self.prepareDirectory(rootURL.appendingPathComponent("devices", isDirectory: true))
        try Self.prepareDirectory(url.deletingLastPathComponent())
        let snapshot = Snapshot(schemaVersion: 1, syntheticDemo: true, fixture: fixture, records: records)
        try atomicWrite(try encoder.encode(snapshot), to: url)
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

    private func readBounded(_ url: URL) throws -> Data {
        try Self.rejectSymlink(url)
        // Check each device directory as well as the file itself.
        if url.lastPathComponent == "records.json" {
            try Self.rejectSymlink(rootURL.appendingPathComponent("devices"))
            try Self.rejectSymlink(url.deletingLastPathComponent())
        }
        return try BoundedFileReader.read(url, maximumBytes: Self.maximumStoreBytes, label: "Store file")
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

    private func atomicWrite(_ data: Data, to url: URL) throws {
        guard data.count <= Self.maximumStoreBytes else {
            throw DeviceBridgeError.invalidStore("Store file exceeds the 4 MiB prototype limit.")
        }
        try Self.rejectSymlink(url)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw Self.posixError("Create atomic demo state file") }
        defer {
            Darwin.close(descriptor)
            Darwin.unlink(temporary.path)
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
        guard Darwin.rename(temporary.path, url.path) == 0 else { throw Self.posixError("Commit demo state") }
        // The new file is now committed. Directory flush is best effort because
        // filesystem support differs; this is not a hardware power-loss guarantee.
        let directory = Darwin.open(url.deletingLastPathComponent().path, O_RDONLY)
        if directory >= 0 {
            _ = Darwin.fsync(directory)
            Darwin.close(directory)
        }
    }

    private static func posixError(_ operation: String) -> NSError {
        let code = errno
        return NSError(domain: NSPOSIXErrorDomain, code: Int(code),
                       userInfo: [NSLocalizedDescriptionKey: "\(operation): \(String(cString: strerror(code)))"])
    }
}
