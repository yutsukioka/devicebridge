import Foundation
import XCTest
@testable import DeviceBridgeCore

@MainActor
final class ControllerCandidateTests: XCTestCase {
    private func withStore(_ body: (URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeviceBridgeControllerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(root)
    }

    func testWaitUntilIdleIncludesJobsEnqueuedWhileWaiting() async throws {
        try await withStore { root in
            let controller = try BridgeController(storeURL: root, stepDelay: .milliseconds(100))
            try controller.enqueue(DemoFixture(device: .aurora))

            var finishedWaiting = false
            var waiter: Task<Void, Never>?
            await withCheckedContinuation { (started: CheckedContinuation<Void, Never>) in
                waiter = Task { @MainActor in
                    started.resume()
                    // The caller can resume on this actor only after this task
                    // suspends in waitUntilIdle, so the second enqueue is later.
                    await controller.waitUntilIdle()
                    finishedWaiting = true
                }
            }
            XCTAssertFalse(finishedWaiting)
            XCTAssertTrue(controller.isRunning)
            try controller.enqueue(DemoFixture(device: .borealis))

            await waiter?.value
            XCTAssertTrue(finishedWaiting)
            XCTAssertFalse(controller.isRunning)
            XCTAssertEqual(controller.jobs.map(\.state), [.completed, .completed])
            XCTAssertFalse(controller.records(for: DemoDeviceKey.aurora.id).messages.isEmpty)
            XCTAssertFalse(controller.records(for: DemoDeviceKey.borealis.id).messages.isEmpty)
        }
    }

    func testHealthyRecoveredRunningJobAllowsEnqueueAndExplicitRetry() async throws {
        try await withStore { root in
            let storage = try FileDeviceStorage(rootURL: root)
            var abandoned = SyncJob(fixture: DemoFixture(device: .aurora))
            abandoned.state = .running
            abandoned.progress = 0.3
            try storage.saveJobs([abandoned])

            let controller = try BridgeController(storage: storage, stepDelay: .milliseconds(1))
            XCTAssertEqual(controller.jobs.first?.state, .interrupted)
            XCTAssertEqual(try storage.loadJobs(), controller.jobs)
            XCTAssertNil(controller.lastError)
            XCTAssertFalse(controller.isRunning)

            try controller.enqueue(DemoFixture(device: .borealis))
            await controller.waitUntilIdle()
            XCTAssertEqual(controller.jobs.map(\.state), [.interrupted, .completed])
            XCTAssertTrue(controller.records(for: DemoDeviceKey.aurora.id).messages.isEmpty)

            try controller.retry(abandoned.id)
            await controller.waitUntilIdle()
            XCTAssertEqual(controller.jobs.map(\.state), [.completed, .completed])
            XCTAssertEqual(controller.jobs.first?.attempt, 2)
            XCTAssertEqual(try storage.loadJobs(), controller.jobs)
            XCTAssertNil(controller.lastError)
        }
    }
}
