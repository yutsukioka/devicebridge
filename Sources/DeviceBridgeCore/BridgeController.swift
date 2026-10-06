import Combine
import Foundation

/// All queue transitions and file writes are serialized on the main actor.
/// There are no device, network, account or credential operations in this class.
@MainActor
public final class BridgeController: ObservableObject {
    @Published public private(set) var devices: [DemoDevice]
    @Published public private(set) var jobs: [SyncJob]
    @Published public private(set) var lastError: String?
    @Published public private(set) var isRunning = false
    @Published public private(set) var revision = 0

    public static var defaultStoreURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DeviceBridge/SyntheticDemo", isDirectory: true)
    }

    private let storage: any DeviceStorage
    private let stepDelay: Duration
    private var deviceRecords: [UUID: DeviceRecords]
    private var worker: Task<Void, Never>?
    private var storageFaulted = false

    public convenience init(storeURL: URL, stepDelay: Duration = .milliseconds(300)) throws {
        try self.init(storage: FileDeviceStorage(rootURL: storeURL), stepDelay: stepDelay)
    }

    /// Injection supports fault tests without pretending security is implemented.
    public init(storage: any DeviceStorage, stepDelay: Duration = .milliseconds(300)) throws {
        self.storage = storage
        self.stepDelay = stepDelay
        self.devices = DemoDeviceKey.allCases.map(DemoDevice.init(key:))
        self.jobs = try storage.loadJobs()
        self.deviceRecords = [:]
        for device in DemoDeviceKey.allCases {
            self.deviceRecords[device.id] = try storage.loadRecords(for: device)
        }
        var recovered = jobs
        for index in recovered.indices where recovered[index].state == .running || recovered[index].state == .queued {
            recovered[index].state = .interrupted
            recovered[index].detail = "Previous session ended before completion. Retry explicitly to continue."
        }
        if recovered != jobs {
            try storage.saveJobs(recovered)
            self.jobs = recovered
        }
        // Never resume disk jobs automatically: the user sees recovered status first.
    }

    public func records(for id: UUID) -> DeviceRecords {
        deviceRecords[id] ?? DeviceRecords()
    }

    public func enqueue(_ fixture: DemoFixture, fault: DemoFault = .none) throws {
        try requireResolvedStorageFailure()
        guard jobs.count < 1_000 else { throw DeviceBridgeError.queueFull }
        var next = jobs
        next.append(SyncJob(fixture: fixture, fault: fault))
        try persist(next)
        startWorkerIfNeeded()
    }

    public func interruptActive() throws {
        try requireResolvedStorageFailure()
        guard let index = jobs.firstIndex(where: { $0.state == .running }) else {
            throw DeviceBridgeError.noActiveJob
        }
        var next = jobs
        next[index].state = .interrupted
        next[index].detail = "Interrupted by the user. Retry explicitly to continue."
        try persist(next)
        // A currently sleeping step checks state before doing any more work.
        startWorkerIfNeeded()
    }

    public func retry(_ id: UUID) throws {
        try requireResolvedStorageFailure()
        guard let index = jobs.firstIndex(where: { $0.id == id }),
              [.failed, .interrupted].contains(jobs[index].state), jobs[index].attempt < 1_000 else {
            throw DeviceBridgeError.cannotRetry
        }
        var next = jobs
        next[index].attempt += 1
        next[index].progress = 0
        next[index].state = .queued
        next[index].detail = "Synthetic Demo retry queued."
        try persist(next)
        startWorkerIfNeeded()
    }

    public func waitUntilIdle() async {
        while let current = worker { await current.value }
    }

    private func startWorkerIfNeeded() {
        guard worker == nil, !jobs.contains(where: { $0.state == .running }),
              jobs.contains(where: { $0.state == .queued }) else { return }
        isRunning = true
        worker = Task { [weak self] in await self?.drainQueue() }
    }

    private func drainQueue() async {
        defer {
            worker = nil
            isRunning = false
        }
        while let job = jobs.first(where: { $0.state == .queued }) {
            do {
                try update(job.id, state: .running, progress: 0.05, detail: "Preparing built-in fictional records.")
                guard await pauseAndCheck(job.id) else { continue }
                try update(job.id, state: .running, progress: 0.30, detail: "Validating the Synthetic Demo scenario.")
                guard await pauseAndCheck(job.id) else { continue }
                if job.fault == .failOnce && job.attempt == 1 {
                    try update(job.id, state: .failed, progress: 0.30,
                               detail: "Simulated failure for testing. Explicit retry will succeed.")
                    continue
                }
                try update(job.id, state: .running, progress: 0.65, detail: "Preparing this device's isolated synthetic snapshot.")
                guard await pauseAndCheck(job.id) else { continue }
                // The journal records this step before the device snapshot is committed.
                try update(job.id, state: .running, progress: 0.85, detail: "Committing this device's fictional records.")
                let records = job.fixture.records()
                try storage.saveRecords(records, fixture: job.fixture)
                deviceRecords[job.deviceID] = records
                revision += 1
                // A crash between snapshot and completion is safe: retry replaces
                // deterministic record IDs instead of appending duplicates.
                try update(job.id, state: .completed, progress: 1, detail: "Synthetic Demo complete. No device was contacted.")
            } catch {
                let failure = error.localizedDescription
                do {
                    var interrupted = jobs
                    if let index = interrupted.firstIndex(where: { $0.id == job.id }) {
                        interrupted[index].state = .interrupted
                        interrupted[index].detail = "Storage operation failed. Restore writable storage, then retry explicitly."
                    }
                    // Only publish recovery if the interrupted state was saved.
                    try storage.saveJobs(interrupted)
                    jobs = interrupted
                    lastError = "Demo storage operation failed: \(failure) The job was saved as interrupted; restore writable storage, then retry."
                } catch {
                    storageFaulted = true
                    lastError = "Demo storage operation failed: \(failure) Recovery could not be saved. Changes are blocked. Restore writable storage, then close and reopen DeviceBridge. The last durable state is preserved."
                }
                return
            }
        }
    }

    private func pauseAndCheck(_ id: UUID) async -> Bool {
        do { try await Task.sleep(for: stepDelay) }
        catch { return false }
        return jobs.first(where: { $0.id == id })?.state == .running
    }

    private func update(_ id: UUID, state: JobState, progress: Double, detail: String) throws {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else {
            throw DeviceBridgeError.invalidStore("The active queue entry is missing.")
        }
        var next = jobs
        next[index].state = state
        next[index].progress = progress
        next[index].detail = detail
        try persist(next)
    }

    private func persist(_ next: [SyncJob]) throws {
        do {
            try storage.saveJobs(next)
            jobs = next
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    private func requireResolvedStorageFailure() throws {
        if storageFaulted {
            throw DeviceBridgeError.invalidStore("Recovery could not be saved. Restore writable storage, then close and reopen DeviceBridge before changing this store.")
        }
        if worker == nil && jobs.contains(where: { $0.state == .running }) {
            throw DeviceBridgeError.invalidStore("A previous job has unresolved state. Restore writable storage, then close and reopen DeviceBridge before changing this store.")
        }
    }
}
