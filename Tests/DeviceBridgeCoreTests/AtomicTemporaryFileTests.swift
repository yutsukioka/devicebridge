import Darwin
import Foundation
import XCTest
@testable import DeviceBridgeCore

@MainActor
final class AtomicTemporaryFileTests: XCTestCase {
    private func withStore(_ body: (URL) throws -> Void) rethrows {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeviceBridgeTemporaryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private func temporaryURL(in directory: URL) -> URL {
        directory.appendingPathComponent(".\(UUID().uuidString).tmp")
    }

    func testReopenRemovesAbandonedWritesAndPreservesCommittedState() async throws {
        try withStore { root in
            var storage: FileDeviceStorage? = try FileDeviceStorage(rootURL: root)
            let jobs = [SyncJob(fixture: DemoFixture(device: .aurora))]
            try storage?.saveJobs(jobs)
            var snapshots: [DemoDeviceKey: DeviceRecords] = [:]
            var abandoned = [temporaryURL(in: root)]
            for device in DemoDeviceKey.allCases {
                let fixture = DemoFixture(device: device)
                let records = fixture.records(updatedAt: Date(timeIntervalSince1970: 100))
                snapshots[device] = records
                try storage?.saveRecords(records, fixture: fixture)
                abandoned.append(temporaryURL(in: try XCTUnwrap(storage).recordsURL(for: device).deletingLastPathComponent()))
            }
            // Model the on-disk state left when a process exits before rename.
            for url in abandoned { try Data("incomplete atomic write".utf8).write(to: url) }
            storage = nil

            let reopened = try FileDeviceStorage(rootURL: root)
            for url in abandoned { XCTAssertFalse(FileManager.default.fileExists(atPath: url.path)) }
            XCTAssertEqual(try reopened.loadJobs(), jobs)
            for device in DemoDeviceKey.allCases {
                XCTAssertEqual(try reopened.loadRecords(for: device), snapshots[device])
            }
        }
    }

    func testCleanupRequiresWriterLock() async throws {
        try withStore { root in
            let active = try FileDeviceStorage(rootURL: root)
            let pending = temporaryURL(in: root)
            let bytes = Data("active writer temporary file".utf8)
            try bytes.write(to: pending)
            XCTAssertThrowsError(try FileDeviceStorage(rootURL: root))
            XCTAssertEqual(try Data(contentsOf: pending), bytes)
            XCTAssertTrue(try active.loadJobs().isEmpty)
        }
    }

    func testCleanupIgnoresUnrelatedNamesAndNonRegularEntries() async throws {
        try withStore { root in
            let fm = FileManager.default
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            let unrelated = root.appendingPathComponent(".not-a-writer-file.tmp")
            let content = Data("preserve".utf8)
            try content.write(to: unrelated)
            let directory = temporaryURL(in: root)
            try fm.createDirectory(at: directory, withIntermediateDirectories: false)
            let nested = directory.appendingPathComponent("keep")
            try content.write(to: nested)
            let link = temporaryURL(in: root)
            try fm.createSymbolicLink(at: link, withDestinationURL: unrelated)
            let pipe = temporaryURL(in: root)
            XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)
            let unknownDevice = root.appendingPathComponent("devices/unrecognized", isDirectory: true)
            try fm.createDirectory(at: unknownDevice, withIntermediateDirectories: true)
            let unknownTemporary = temporaryURL(in: unknownDevice)
            try content.write(to: unknownTemporary)

            let storage = try FileDeviceStorage(rootURL: root)
            XCTAssertEqual(try Data(contentsOf: unrelated), content)
            XCTAssertEqual(try Data(contentsOf: nested), content)
            XCTAssertEqual(try Data(contentsOf: unknownTemporary), content)
            XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: link.path), unrelated.path)
            var info = stat()
            XCTAssertEqual(Darwin.lstat(pipe.path, &info), 0)
            XCTAssertEqual(info.st_mode & S_IFMT, S_IFIFO)
            XCTAssertTrue(try storage.loadJobs().isEmpty)
        }
    }
}
