import Foundation

public extension DemoFixture {
    /// Stable IDs, timestamps and fictional text make retries idempotent.
    func records(updatedAt: Date = Date()) -> DeviceRecords {
        let prefix = device == .aurora ? "A1000000" : "B2000000"
        func identifier(_ value: Int) -> UUID {
            UUID(uuidString: String(format: "%@-0000-4000-8000-%012d", prefix, value))!
        }
        let origin = Date(timeIntervalSince1970: 1_790_899_200) // Fixed demo timeline.
        let contact = device == .aurora ? "Alex Example (fictional)" : "Taylor Sample (fictional)"
        let other = device == .aurora ? "Morgan Demo (fictional)" : "Casey Demo (fictional)"
        let shift: TimeInterval = device == .aurora ? 0 : 1800
        let count = scenario == .baseline ? 3 : 4
        let calls = (0..<count).map { index in
            CallRecord(id: identifier(100 + index), contact: index.isMultiple(of: 2) ? contact : other,
                       timestamp: origin.addingTimeInterval(shift + Double(index) * 3600),
                       direction: index.isMultiple(of: 2) ? "Incoming" : "Outgoing",
                       durationSeconds: [124, 48, 305, 90][index])
        }
        let text = [
            "Synthetic Demo: The fictional observatory tour starts at noon.",
            "Synthetic Demo: I will bring the imaginary star chart.",
            "Synthetic Demo: The pretend meeting moved to the blue room.",
            "Synthetic Demo: Thanks for testing this fictional conversation.",
            "Synthetic Demo refresh: The imaginary comet display is ready."
        ]
        let messageCount = scenario == .baseline ? 4 : 5
        let messages = (0..<messageCount).map { index in
            MessageRecord(id: identifier(200 + index), contact: index.isMultiple(of: 2) ? contact : other,
                          timestamp: origin.addingTimeInterval(shift + Double(index) * 2100 + 600),
                          direction: index.isMultiple(of: 2) ? "Incoming" : "Outgoing", body: text[index])
        }
        return DeviceRecords(calls: calls, messages: messages, updatedAt: updatedAt)
    }
}
