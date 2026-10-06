import AppKit
import DeviceBridgeCore
import SwiftUI

@main
struct DeviceBridgeApp: App {
    @StateObject private var application = ApplicationModel()

    var body: some Scene {
        WindowGroup("DeviceBridge") {
            GeometryReader { viewport in
                Group {
                    if let controller = application.controller {
                        DeviceBridgeView(controller: controller)
                    } else {
                        StartupFailureView(message: application.startupError ?? "The local demo store could not be opened.")
                    }
                }
                .frame(width: viewport.size.width, height: viewport.size.height, alignment: .topLeading)
            }
            .frame(minWidth: 1040, minHeight: 680)
            .onAppear {
                NSApplication.shared.setActivationPolicy(.regular)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
        .defaultSize(width: 1260, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

@MainActor
private final class ApplicationModel: ObservableObject {
    @Published var controller: BridgeController?
    @Published var startupError: String?

    init() {
        do {
            let storeURL: URL
            if let index = CommandLine.arguments.firstIndex(of: "--store-root") {
                guard CommandLine.arguments.indices.contains(index + 1),
                      !CommandLine.arguments[index + 1].hasPrefix("--") else {
                    throw LaunchError.missingStorePath
                }
                storeURL = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
            } else {
                storeURL = BridgeController.defaultStoreURL
            }
            let bridge = try BridgeController(storeURL: storeURL, stepDelay: .seconds(1))
            // An empty queue is a new demo store. Durable job history prevents reseeding on restart.
            if bridge.jobs.isEmpty {
                try bridge.enqueue(DemoFixture(device: .aurora))
                try bridge.enqueue(DemoFixture(device: .borealis))
            }
            controller = bridge
        } catch {
            startupError = error.localizedDescription
        }
    }
}

private enum LaunchError: LocalizedError {
    case missingStorePath
    var errorDescription: String? {
        "The --store-root argument needs a directory path. The demo was not started."
    }
}

private struct StartupFailureView: View {
    let message: String

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.orange)
            Text("The demo store could not be opened")
                .font(.title2.bold())
            Text(message)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 580)
            Text("Review the storage error before continuing. Quit and restart with an empty --store-root directory to try an isolated demo.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 580)
            Button("Quit DeviceBridge") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(48)
    }
}
