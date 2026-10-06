#if !arch(arm64)
#error("DeviceBridge requires a native arm64 build. Intel and Rosetta builds are unsupported.")
#endif

import Foundation

public enum DemoDeviceKey: String, Codable, CaseIterable, Sendable {
    case aurora, borealis

    public var id: UUID {
        UUID(uuidString: self == .aurora
            ? "A1000000-0000-4000-8000-000000000001"
            : "B2000000-0000-4000-8000-000000000002")!
    }

    public var displayName: String {
        self == .aurora ? "Aurora — Synthetic Demo" : "Borealis — Synthetic Demo"
    }

    public init?(id: UUID) {
        guard let key = Self.allCases.first(where: { $0.id == id }) else { return nil }
        self = key
    }
}

public enum DemoScenario: String, Codable, CaseIterable, Sendable {
    case baseline, refresh
}

public enum DemoFault: String, Codable, CaseIterable, Sendable {
    case none, failOnce
}

/// The only supported import is a selector for built-in fictional data.
/// There is intentionally no import field for a contact, phone number, or message body.
public struct DemoFixture: Codable, Equatable, Sendable {
    public let device: DemoDeviceKey
    public let scenario: DemoScenario
    public static let maximumFileBytes = 16_384

    public init(device: DemoDeviceKey, scenario: DemoScenario = .baseline) {
        self.device = device
        self.scenario = scenario
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, syntheticDemo, device, scenario
    }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public init(from decoder: any Decoder) throws {
        let all = try decoder.container(keyedBy: AnyKey.self)
        let actual = Set(all.allKeys.map(\.stringValue))
        let expected = Set(CodingKeys.allCases.map(\.rawValue))
        guard actual == expected else {
            throw DeviceBridgeError.invalidFixture("Exactly schemaVersion, syntheticDemo, device and scenario are required. Record content is never accepted.")
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion) == 1,
              try container.decode(Bool.self, forKey: .syntheticDemo) else {
            throw DeviceBridgeError.invalidFixture("Only version 1 Synthetic Demo fixtures are supported.")
        }
        device = try container.decode(DemoDeviceKey.self, forKey: .device)
        scenario = try container.decode(DemoScenario.self, forKey: .scenario)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(1, forKey: .schemaVersion)
        try container.encode(true, forKey: .syntheticDemo)
        try container.encode(device, forKey: .device)
        try container.encode(scenario, forKey: .scenario)
    }

    public static func load(from url: URL) throws -> DemoFixture {
        let data = try BoundedFileReader.read(url, maximumBytes: maximumFileBytes, label: "Fixture")
        return try JSONDecoder().decode(DemoFixture.self, from: data)
    }
}

public struct DemoDevice: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String

    public init(key: DemoDeviceKey) {
        id = key.id
        name = key.displayName
    }
}

public struct CallRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let contact: String
    public let timestamp: Date
    public let direction: String
    public let durationSeconds: Int
}

public struct MessageRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let contact: String
    public let timestamp: Date
    public let direction: String
    public let body: String
}

public struct DeviceRecords: Codable, Equatable, Sendable {
    public var calls: [CallRecord]
    public var messages: [MessageRecord]
    public var updatedAt: Date?

    public init(calls: [CallRecord] = [], messages: [MessageRecord] = [], updatedAt: Date? = nil) {
        self.calls = calls
        self.messages = messages
        self.updatedAt = updatedAt
    }
}

public enum JobState: String, Codable, CaseIterable, Sendable {
    case queued, running, interrupted, failed, completed

    public var displayName: String { rawValue.capitalized }
}

public struct SyncJob: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let fixture: DemoFixture
    public let fault: DemoFault
    public var state: JobState
    public var progress: Double
    public var attempt: Int
    public var detail: String
    public var deviceID: UUID { fixture.device.id }
    public var deviceName: String { fixture.device.displayName }

    public init(id: UUID = UUID(), fixture: DemoFixture, fault: DemoFault = .none) {
        self.id = id
        self.fixture = fixture
        self.fault = fault
        self.state = .queued
        self.progress = 0
        self.attempt = 1
        self.detail = "Synthetic Demo queued."
    }
}

public enum DeviceBridgeError: LocalizedError {
    case invalidFixture(String)
    case invalidStore(String)
    case storeInUse
    case noActiveJob
    case cannotRetry
    case queueFull

    public var errorDescription: String? {
        switch self {
        case .invalidFixture(let reason): return "Invalid Synthetic Demo fixture: \(reason)"
        case .invalidStore(let reason): return "Synthetic Demo storage error: \(reason)"
        case .storeInUse: return "This Synthetic Demo store is already open in another DeviceBridge process. Close it or choose a different store directory."
        case .noActiveJob: return "There is no active Synthetic Demo job to interrupt."
        case .cannotRetry: return "Only failed or interrupted Synthetic Demo jobs can be retried."
        case .queueFull: return "The prototype queue is limited to 1,000 jobs. Choose a new demo store to start another session."
        }
    }
}
