import Foundation
import DeviceBridgeCore
import Darwin

@main
struct FixtureHarness {
    @MainActor
    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments.isEmpty || arguments.contains("--help") {
                print(usage)
                return
            }
            guard let command = arguments.first,
                  ["seed", "import", "status", "interrupt-demo", "failure-demo", "checkpoint-interruption"].contains(command) else {
                throw HarnessError.usage("Unknown command.")
            }
            var options: [String: String] = [:]
            var index = 1
            while index < arguments.count {
                let key = arguments[index]
                guard ["--store", "--fixture"].contains(key), index + 1 < arguments.count,
                      options[key] == nil else { throw HarnessError.usage("Invalid or duplicate option: \(key)") }
                options[key] = arguments[index + 1]
                index += 2
            }
            guard let path = options["--store"], !path.isEmpty else {
                throw HarnessError.usage("Every command requires --store PATH to an explicit demo storage directory.")
            }
            if options["--fixture"] != nil && command != "import" {
                throw HarnessError.usage("--fixture is only supported by import.")
            }
            let fixture: DemoFixture?
            if command == "import" {
                guard let path = options["--fixture"] else { throw HarnessError.usage("import requires --fixture PATH.") }
                fixture = try DemoFixture.load(from: URL(fileURLWithPath: path))
            } else { fixture = nil }
            let controller = try BridgeController(storeURL: URL(fileURLWithPath: path, isDirectory: true))
            switch command {
            case "seed":
                try controller.enqueue(DemoFixture(device: .aurora))
                try controller.enqueue(DemoFixture(device: .borealis))
            case "import":
                if let fixture { try controller.enqueue(fixture) }
            case "failure-demo":
                try controller.enqueue(DemoFixture(device: .aurora, scenario: .refresh), fault: .failOnce)
                await controller.waitUntilIdle()
                guard let failed = controller.jobs.last(where: { $0.state == .failed }) else {
                    throw HarnessError.verification("Expected a visible failure.")
                }
                print("Verified failed attempt \(failed.attempt); explicitly retrying.")
                try controller.retry(failed.id)
            case "interrupt-demo":
                try controller.enqueue(DemoFixture(device: .aurora, scenario: .refresh))
                try await waitForRunning(controller)
                try controller.interruptActive()
                await controller.waitUntilIdle()
                guard let interrupted = controller.jobs.last(where: { $0.state == .interrupted }) else {
                    throw HarnessError.verification("Expected an interrupted job.")
                }
                print("Verified interrupted attempt \(interrupted.attempt); explicitly retrying.")
                try controller.retry(interrupted.id)
            case "checkpoint-interruption":
                try controller.enqueue(DemoFixture(device: .aurora, scenario: .refresh))
                try await waitForRunning(controller)
                FileHandle.standardOutput.write(Data("Leaving a durable running checkpoint; reopen with status to verify recovery.\n".utf8))
                // Intentionally skip application cleanup. The OS releases the process lock.
                // This exercises abrupt process exit, not physical power-loss durability.
                exit(0)
            default: break
            }
            await controller.waitUntilIdle()
            report(controller)
            if let error = controller.lastError { throw HarnessError.verification(error) }
            if command != "status", controller.jobs.contains(where: { $0.state == .failed }) {
                throw HarnessError.verification("A job failed; inspect the visible queue details.")
            }
        } catch {
            FileHandle.standardError.write(Data("DeviceBridge: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    @MainActor
    private static func waitForRunning(_ controller: BridgeController) async throws {
        for _ in 0..<100 {
            if controller.jobs.contains(where: { $0.state == .running }) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw HarnessError.verification("Timed out waiting for a running demo job.")
    }

    @MainActor
    private static func report(_ controller: BridgeController) {
        print("DeviceBridge • Synthetic Demo • No physical devices accessed")
        for device in controller.devices {
            let records = controller.records(for: device.id)
            print("\(device.name): \(records.calls.count) fictional calls, \(records.messages.count) fictional messages")
        }
        for job in controller.jobs {
            print("\(job.id.uuidString) | \(job.deviceName) | \(job.state.rawValue) | attempt \(job.attempt) | \(job.detail)")
        }
    }

    private static let usage = """
    DeviceBridge synthetic fixture harness (arm64)
    Usage: devicebridge-fixtures COMMAND --store PATH [--fixture PATH]
      seed                     Import both built-in fictional devices
      import --fixture PATH    Import one strict scenario JSON (not real records)
      status                   Show records/jobs; recover abandoned jobs as interrupted
      failure-demo             Fail once, then explicitly retry
      interrupt-demo           Interrupt a running job, then explicitly retry
      checkpoint-interruption  Exit with a saved running job for next-launch recovery
    Use a dedicated temporary directory for --store. No network or device access.
    """
}

private enum HarnessError: LocalizedError {
    case usage(String)
    case verification(String)
    var errorDescription: String? {
        switch self {
        case .usage(let detail): return detail + " Run with --help for syntax."
        case .verification(let detail): return detail
        }
    }
}
