import XCTest
import Foundation
import Darwin
@testable import DeviceBridgeCore

@MainActor
final class DeviceBridgeCoreTests: XCTestCase {
    private func withStore(_ body: (URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DeviceBridgeTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(root)
    }

    func testDeviceIsolationAndDeterministicReimport() async throws {
        try await withStore { root in
            let controller = try BridgeController(storeURL: root)
            try controller.enqueue(DemoFixture(device: .aurora))
            await controller.waitUntilIdle()
            let aurora = controller.records(for: DemoDeviceKey.aurora.id)
            XCTAssertFalse(aurora.calls.isEmpty)
            XCTAssertFalse(aurora.messages.isEmpty)
            XCTAssertTrue(controller.records(for: DemoDeviceKey.borealis.id).calls.isEmpty)
            try controller.enqueue(DemoFixture(device: .borealis))
            await controller.waitUntilIdle()
            let borealis = controller.records(for: DemoDeviceKey.borealis.id)
            XCTAssertFalse(borealis.messages.isEmpty)
            XCTAssertTrue(Set(aurora.messages.map(\.id)).isDisjoint(with: Set(borealis.messages.map(\.id))))
            try controller.enqueue(DemoFixture(device: .aurora))
            await controller.waitUntilIdle()
            XCTAssertEqual(controller.records(for: DemoDeviceKey.aurora.id).calls.map(\.id), aurora.calls.map(\.id))
            XCTAssertEqual(controller.records(for: DemoDeviceKey.aurora.id).messages.map(\.id), aurora.messages.map(\.id))
            XCTAssertEqual(controller.records(for: DemoDeviceKey.borealis.id).messages.map(\.id), borealis.messages.map(\.id))
        }
    }

    func testQueueNeverRunsTwoJobsTogether() async throws {
        try await withStore { root in
            let controller = try BridgeController(storeURL: root)
            try controller.enqueue(DemoFixture(device: .aurora))
            try controller.enqueue(DemoFixture(device: .borealis))
            var sawRunning = false
            for _ in 0..<400 {
                let running = controller.jobs.filter { $0.state == .running }
                XCTAssertLessThanOrEqual(running.count, 1)
                sawRunning = sawRunning || !running.isEmpty
                if controller.jobs.allSatisfy({ $0.state == .completed }) { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            await controller.waitUntilIdle()
            XCTAssertTrue(sawRunning)
            XCTAssertEqual(controller.jobs.map(\.state), [.completed, .completed])
        }
    }

    func testFailureIsVisibleAndRetrySucceedsWithoutDuplicates() async throws {
        try await withStore { root in
            let controller = try BridgeController(storeURL: root)
            try controller.enqueue(DemoFixture(device: .aurora), fault: .failOnce)
            try controller.enqueue(DemoFixture(device: .borealis))
            await controller.waitUntilIdle()
            let failed = try XCTUnwrap(controller.jobs.first { $0.state == .failed })
            XCTAssertFalse(failed.detail.isEmpty)
            XCTAssertEqual(failed.attempt, 1)
            XCTAssertTrue(controller.records(for: DemoDeviceKey.aurora.id).calls.isEmpty)
            XCTAssertEqual(controller.jobs.last?.state, .completed)
            try controller.retry(failed.id)
            await controller.waitUntilIdle()
            let retried = try XCTUnwrap(controller.jobs.first { $0.id == failed.id })
            XCTAssertEqual(retried.state, .completed)
            XCTAssertEqual(retried.attempt, 2)
            XCTAssertEqual(controller.jobs.count, 2)
            XCTAssertFalse(controller.records(for: DemoDeviceKey.aurora.id).calls.isEmpty)
            XCTAssertThrowsError(try controller.retry(failed.id))
        }
    }

    func testInterruptionRequiresExplicitRetry() async throws {
        try await withStore { root in
            let controller = try BridgeController(storeURL: root)
            try controller.enqueue(DemoFixture(device: .aurora))
            for _ in 0..<100 {
                if controller.jobs.first?.state == .running { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertEqual(controller.jobs.first?.state, .running)
            try controller.interruptActive()
            await controller.waitUntilIdle()
            let interrupted = try XCTUnwrap(controller.jobs.first)
            XCTAssertEqual(interrupted.state, .interrupted)
            XCTAssertTrue(controller.records(for: DemoDeviceKey.aurora.id).messages.isEmpty)
            try controller.retry(interrupted.id)
            await controller.waitUntilIdle()
            XCTAssertEqual(controller.jobs.first?.state, .completed)
            XCTAssertEqual(controller.jobs.first?.attempt, 2)
        }
    }

    func testConcurrentStoreAccessIsRejected() async throws {
        try await withStore { root in
            let controller = try BridgeController(storeURL: root)
            XCTAssertThrowsError(try BridgeController(storeURL: root))
            XCTAssertEqual(controller.devices.count, 2)
        }
    }

    func testCompletedRecordsSurviveReopening() async throws {
        try await withStore { root in
            var controller: BridgeController? = try BridgeController(storeURL: root)
            try controller?.enqueue(DemoFixture(device: .aurora))
            await controller?.waitUntilIdle()
            let ids = controller?.records(for: DemoDeviceKey.aurora.id).messages.map(\.id)
            controller = nil
            let reopened = try BridgeController(storeURL: root)
            XCTAssertEqual(reopened.records(for: DemoDeviceKey.aurora.id).messages.map(\.id), ids)
            XCTAssertEqual(reopened.jobs.first?.state, .completed)
            XCTAssertFalse(reopened.isRunning)
        }
    }

    func testFixtureAllowsOnlyKnownSyntheticScenarios() async throws {
        try await withStore { root in
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let file = root.appendingPathComponent("fixture.json")
            let valid = #"{"schemaVersion":1,"syntheticDemo":true,"device":"aurora","scenario":"refresh"}"#
            try Data(valid.utf8).write(to: file)
            _ = try DemoFixture.load(from: file)
            let invalidFixtures = [
                valid.replacingOccurrences(of: "true", with: "false"),
                valid.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":99"),
                valid.replacingOccurrences(of: "aurora", with: "../outside"),
                valid.replacingOccurrences(of: "refresh", with: "personal-backup"),
                valid.replacingOccurrences(of: "}", with: ",\"messages\":[\"PRIVATE\"]}"),
                "{}", "not json", String(repeating: " ", count: 16_385)
            ]
            for input in invalidFixtures {
                try Data(input.utf8).write(to: file)
                XCTAssertThrowsError(try DemoFixture.load(from: file), "Unexpectedly accepted: \(input.prefix(100))")
            }
        }
    }

    func testStorageWriteFailureBecomesRetryableInterruption() async throws {
        let storage = FaultStorage()
        storage.failSnapshot = true
        let controller = try BridgeController(storage: storage)
        try controller.enqueue(DemoFixture(device: .aurora))
        await controller.waitUntilIdle()
        XCTAssertEqual(controller.jobs.first?.state, .interrupted)
        XCTAssertNotNil(controller.lastError)
        XCTAssertTrue(controller.records(for: DemoDeviceKey.aurora.id).calls.isEmpty)
        storage.failSnapshot = false
        try controller.retry(XCTUnwrap(controller.jobs.first?.id))
        await controller.waitUntilIdle()
        XCTAssertEqual(controller.jobs.first?.state, .completed)
        XCTAssertNil(controller.lastError)
    }

    func testRestartRecoversBothQueuedAndRunningJobsWithoutStartingWork() async throws {
        let storage = FaultStorage()
        let queued = SyncJob(fixture: DemoFixture(device: .aurora))
        var running = SyncJob(fixture: DemoFixture(device: .borealis))
        running.state = .running
        running.progress = 0.3
        storage.jobs = [queued, running]
        let controller = try BridgeController(storage: storage)
        XCTAssertEqual(controller.jobs.map(\.state), [.interrupted, .interrupted])
        XCTAssertEqual(controller.jobs.map(\.id), [queued.id, running.id])
        XCTAssertEqual(controller.jobs, storage.jobs)
        XCTAssertFalse(controller.isRunning)
        XCTAssertTrue(controller.records(for: DemoDeviceKey.borealis.id).messages.isEmpty)
    }

    func testCrossDeviceSnapshotsCannotBeStored() async throws {
        try await withStore { root in
            let storage = try FileDeviceStorage(rootURL: root)
            let aurora = DemoFixture(device: .aurora)
            let borealis = DemoFixture(device: .borealis)
            XCTAssertThrowsError(try storage.saveRecords(aurora.records(), fixture: borealis))
            XCTAssertTrue(try storage.loadRecords(for: .borealis).messages.isEmpty)
        }
    }

    func testPersistentDiskFailureBlocksMoreJobsAndPreservesCheckpoint() async throws {
        let storage = FaultStorage()
        storage.failSnapshot = true
        storage.failRecoveryJournal = true
        let controller = try BridgeController(storage: storage)
        try controller.enqueue(DemoFixture(device: .aurora))
        await controller.waitUntilIdle()
        XCTAssertFalse(controller.isRunning)
        XCTAssertEqual(controller.jobs.first?.state, .running)
        XCTAssertNotNil(controller.lastError)
        XCTAssertThrowsError(try controller.enqueue(DemoFixture(device: .borealis)))
        XCTAssertThrowsError(try controller.interruptActive())
        XCTAssertEqual(controller.jobs.count, 1)
        XCTAssertEqual(controller.jobs, storage.jobs)
    }

    func testCorruptStoreIsReportedWithoutResettingFile() async throws {
        try await withStore { root in
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let queue = root.appendingPathComponent("queue.json")
            let corrupt = Data("corrupt demo queue".utf8)
            try corrupt.write(to: queue)
            XCTAssertThrowsError(try BridgeController(storeURL: root))
            XCTAssertEqual(try Data(contentsOf: queue), corrupt)
        }
    }

    func testNonRegularFixtureAndStoreAreRejectedWithoutBlocking() async throws {
        try await withStore { root in
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let pipe = root.appendingPathComponent("fixture.json")
            XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)
            XCTAssertThrowsError(try DemoFixture.load(from: pipe))
            let queue = root.appendingPathComponent("queue.json")
            XCTAssertEqual(mkfifo(queue.path, 0o600), 0)
            XCTAssertThrowsError(try BridgeController(storeURL: root))
        }
    }
}

@MainActor
private final class FaultStorage: DeviceStorage {
    var jobs: [SyncJob] = []
    var snapshots: [DemoDeviceKey: DeviceRecords] = [:]
    var failSnapshot = false
    var failRecoveryJournal = false
    private var snapshotFailed = false
    func loadJobs() throws -> [SyncJob] { jobs }
    func saveJobs(_ jobs: [SyncJob]) throws {
        if snapshotFailed && failRecoveryJournal { throw CocoaError(.fileWriteOutOfSpace) }
        self.jobs = jobs
    }
    func loadRecords(for device: DemoDeviceKey) throws -> DeviceRecords { snapshots[device] ?? DeviceRecords() }
    func saveRecords(_ records: DeviceRecords, fixture: DemoFixture) throws {
        if failSnapshot {
            snapshotFailed = true
            throw CocoaError(.fileWriteOutOfSpace)
        }
        snapshots[fixture.device] = records
    }
}
