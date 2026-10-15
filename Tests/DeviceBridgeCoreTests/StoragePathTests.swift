import XCTest
import Foundation
@testable import DeviceBridgeCore

@MainActor
final class StoragePathTests: XCTestCase {
    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeviceBridgePathTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try body(base)
    }

    func testReplacingOpenStoreRootCannotRedirectQueueAccess() async throws {
        try withDirectory { base in
            let source = base.appendingPathComponent("source", isDirectory: true)
            let moved = base.appendingPathComponent("source-moved", isDirectory: true)
            let other = base.appendingPathComponent("other", isDirectory: true)
            let sourceStorage = try FileDeviceStorage(rootURL: source)
            let otherStorage = try FileDeviceStorage(rootURL: other)
            let sourceJobs = [SyncJob(fixture: DemoFixture(device: .aurora))]
            let otherJobs = [SyncJob(fixture: DemoFixture(device: .borealis))]
            try sourceStorage.saveJobs(sourceJobs)
            try otherStorage.saveJobs(otherJobs)
            let otherQueue = other.appendingPathComponent("queue.json")
            let otherBytes = try Data(contentsOf: otherQueue)
            try FileManager.default.moveItem(at: source, to: moved)
            try FileManager.default.createSymbolicLink(at: source, withDestinationURL: other)

            // Refusing the replaced path or continuing in the original directory
            // is safe. Accessing the replacement store is never safe, especially
            // while that store's own writer holds its independent lock.
            if let loaded = try? sourceStorage.loadJobs() {
                XCTAssertEqual(loaded, sourceJobs)
            }
            try? sourceStorage.saveJobs(sourceJobs)
            XCTAssertEqual(try Data(contentsOf: otherQueue), otherBytes)
            XCTAssertEqual(try otherStorage.loadJobs(), otherJobs)
            XCTAssertThrowsError(try FileDeviceStorage(rootURL: moved))
        }
    }

    func testReplacingOpenStoreAncestorCannotRedirectSnapshotAccess() async throws {
        try withDirectory { base in
            let parent = base.appendingPathComponent("parent", isDirectory: true)
            let movedParent = base.appendingPathComponent("parent-moved", isDirectory: true)
            let otherParent = base.appendingPathComponent("other-parent", isDirectory: true)
            let source = parent.appendingPathComponent("store", isDirectory: true)
            let other = otherParent.appendingPathComponent("store", isDirectory: true)
            let sourceStorage = try FileDeviceStorage(rootURL: source)
            let otherStorage = try FileDeviceStorage(rootURL: other)
            let baseline = DemoFixture(device: .aurora)
            let refresh = DemoFixture(device: .aurora, scenario: .refresh)
            let sourceRecords = baseline.records(updatedAt: Date(timeIntervalSince1970: 100))
            let otherRecords = refresh.records(updatedAt: Date(timeIntervalSince1970: 200))
            try sourceStorage.saveRecords(sourceRecords, fixture: baseline)
            try otherStorage.saveRecords(otherRecords, fixture: refresh)
            let otherURL = otherStorage.recordsURL(for: .aurora)
            let otherBytes = try Data(contentsOf: otherURL)
            try FileManager.default.moveItem(at: parent, to: movedParent)
            try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: otherParent)

            if let loaded = try? sourceStorage.loadRecords(for: .aurora) {
                XCTAssertEqual(loaded, sourceRecords)
            }
            try? sourceStorage.saveRecords(sourceRecords, fixture: baseline)
            XCTAssertEqual(try Data(contentsOf: otherURL), otherBytes)
            XCTAssertEqual(try otherStorage.loadRecords(for: .aurora), otherRecords)
            XCTAssertThrowsError(try FileDeviceStorage(rootURL: movedParent.appendingPathComponent("store")))
        }
    }

    func testReplacingDevicesDirectoryWithSymlinkCannotRedirectSnapshotAccess() async throws {
        try assertChildSymlinkCannotRedirectSnapshotAccess(replaceDeviceDirectory: false)
    }

    func testReplacingDeviceDirectoryWithSymlinkCannotRedirectSnapshotAccess() async throws {
        try assertChildSymlinkCannotRedirectSnapshotAccess(replaceDeviceDirectory: true)
    }

    private func assertChildSymlinkCannotRedirectSnapshotAccess(replaceDeviceDirectory: Bool) throws {
        try withDirectory { base in
            let sourceStorage = try FileDeviceStorage(rootURL: base.appendingPathComponent("source"))
            let otherStorage = try FileDeviceStorage(rootURL: base.appendingPathComponent("other"))
            let baseline = DemoFixture(device: .aurora)
            let refresh = DemoFixture(device: .aurora, scenario: .refresh)
            let sourceRecords = baseline.records(updatedAt: Date(timeIntervalSince1970: 100))
            let otherRecords = refresh.records(updatedAt: Date(timeIntervalSince1970: 200))
            try sourceStorage.saveRecords(sourceRecords, fixture: baseline)
            try otherStorage.saveRecords(otherRecords, fixture: refresh)
            let sourceURL = sourceStorage.recordsURL(for: .aurora)
            let otherURL = otherStorage.recordsURL(for: .aurora)
            let otherBytes = try Data(contentsOf: otherURL)
            let sourceDirectory = replaceDeviceDirectory
                ? sourceURL.deletingLastPathComponent()
                : sourceStorage.rootURL.appendingPathComponent("devices")
            let otherDirectory = replaceDeviceDirectory
                ? otherURL.deletingLastPathComponent()
                : otherStorage.rootURL.appendingPathComponent("devices")
            try FileManager.default.moveItem(at: sourceDirectory, to: base.appendingPathComponent("moved"))
            try FileManager.default.createSymbolicLink(at: sourceDirectory, withDestinationURL: otherDirectory)

            XCTAssertThrowsError(try sourceStorage.loadRecords(for: .aurora))
            XCTAssertThrowsError(try sourceStorage.saveRecords(sourceRecords, fixture: baseline))
            XCTAssertEqual(try Data(contentsOf: otherURL), otherBytes)
            XCTAssertEqual(try otherStorage.loadRecords(for: .aurora), otherRecords)
        }
    }

    func testDanglingQueueSymlinkIsReportedInsteadOfReturningEmptyQueue() async throws {
        try withDirectory { base in
            let storage = try FileDeviceStorage(rootURL: base.appendingPathComponent("store"))
            let queue = storage.rootURL.appendingPathComponent("queue.json")
            let missing = base.appendingPathComponent("missing-queue.json")
            try FileManager.default.createSymbolicLink(at: queue, withDestinationURL: missing)
            XCTAssertThrowsError(try storage.loadJobs())
            XCTAssertThrowsError(try storage.saveJobs([]))
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: queue.path), missing.path)
            XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        }
    }

    func testDanglingSnapshotSymlinkIsReportedInsteadOfReturningEmptyRecords() async throws {
        try withDirectory { base in
            let storage = try FileDeviceStorage(rootURL: base.appendingPathComponent("store"))
            let fixture = DemoFixture(device: .aurora)
            let records = fixture.records(updatedAt: Date(timeIntervalSince1970: 100))
            try storage.saveRecords(records, fixture: fixture)
            let snapshot = storage.recordsURL(for: .aurora)
            let missing = base.appendingPathComponent("missing-records.json")
            try FileManager.default.removeItem(at: snapshot)
            try FileManager.default.createSymbolicLink(at: snapshot, withDestinationURL: missing)
            XCTAssertThrowsError(try storage.loadRecords(for: .aurora))
            XCTAssertThrowsError(try storage.saveRecords(records, fixture: fixture))
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: snapshot.path), missing.path)
            XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        }
    }
}
