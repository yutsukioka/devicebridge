import DeviceBridgeCore
import SwiftUI
import UniformTypeIdentifiers

struct DeviceBridgeView: View {
    @ObservedObject var controller: BridgeController
    @State private var selectedDeviceID: UUID?
    @State private var selectedHistory: HistoryKind = .messages
    @State private var query = ""
    @State private var showingImporter = false
    @State private var showingAbout = false
    @State private var actionError: String?

    private var selectedDevice: DemoDevice? {
        controller.devices.first { $0.id == selectedDeviceID } ?? controller.devices.first
    }

    var body: some View {
        NavigationSplitView {
            GeometryReader { column in
                sidebar
                    .frame(width: column.size.width, height: column.size.height, alignment: .top)
            }
            .navigationSplitViewColumnWidth(min: 205, ideal: 225, max: 270)
        } detail: {
            GeometryReader { column in
                VStack(spacing: 0) {
                    demoBanner
                    if let device = selectedDevice {
                        detail(for: device)
                    } else {
                        ContentUnavailableView("No demo devices", systemImage: "iphone", description: Text("Import a supported synthetic fixture to begin."))
                    }
                    footer
                }
                .frame(width: column.size.width, height: column.size.height, alignment: .top)
            }
        }
        .tint(.teal)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingImporter = true
                } label: {
                    Label("Import fixture", systemImage: "square.and.arrow.down")
                }
                .help("Import a validated DeviceBridge synthetic JSON fixture")
                Button {
                    showingAbout = true
                } label: {
                    Label("About this demo", systemImage: "info.circle")
                }
                .help("Read prototype capabilities and limitations")
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            perform {
                guard let url = try result.get().first else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                try controller.enqueue(DemoFixture.load(from: url))
            }
        }
        .sheet(isPresented: $showingAbout) { DemoAboutView() }
        .alert("Demo action could not be completed", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "Unknown error")
        }
        .onAppear {
            if selectedDeviceID == nil { selectedDeviceID = controller.devices.first?.id }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.title2)
                    .foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("DeviceBridge").font(.headline)
                    Text("Local prototype").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(20)

            List(selection: $selectedDeviceID) {
                Section("Demo devices") {
                    ForEach(controller.devices, id: \.id) { device in
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: "iphone")
                                .font(.system(size: 25, weight: .light))
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(device.name).font(.body.weight(.medium))
                                Text(deviceStatus(device.id))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Circle()
                                .fill(deviceActivityColor(device.id))
                                .frame(width: 6, height: 6)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 6)
                        .tag(device.id)
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minHeight: 0, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 8) {
                Label("No physical connections", systemImage: "cable.connector.slash")
                    .font(.caption.weight(.medium))
                Text("Devices and records in this app are fictional. USB and Wi-Fi sync are future work.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
        }
    }

    private var demoBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "testtube.2").font(.title3)
            Text("SYNTHETIC DEMO")
                .font(.caption.weight(.bold))
                .tracking(1.2)
            Text("Fictional calls and messages. No real device data is accessed.")
                .font(.callout)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.teal)
        .padding(.horizontal, 24)
        .padding(.vertical, 13)
        .background(Color.teal.opacity(0.09))
    }

    private func detail(for device: DemoDevice) -> some View {
        let records = controller.records(for: device.id)
        return VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(device.name).font(.system(size: 30, weight: .semibold, design: .rounded))
                    HStack(spacing: 5) {
                        Text("Fictional device")
                        Text("·")
                        if let updated = records.updatedAt {
                            Text("Last fixture applied \(updated.formatted(date: .abbreviated, time: .shortened))")
                        } else {
                            Text("Waiting for the first fixture")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Queue synthetic refresh", systemImage: "arrow.clockwise") {
                        enqueue(device: device, fault: .none)
                    }
                    Button("Simulate one failed attempt", systemImage: "exclamationmark.arrow.triangle.2.circlepath") {
                        enqueue(device: device, fault: .failOnce)
                    }
                } label: {
                    Label("Run demo", systemImage: "play.fill")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.teal.opacity(0.11), in: RoundedRectangle(cornerRadius: 9))
                .help("Queue a synthetic refresh or an intentional failure for this device")
            }

            HStack(spacing: 12) {
                SummaryCard(title: "Messages", value: String(records.messages.count), symbol: "bubble.left.and.bubble.right", footnote: "Synthetic records")
                SummaryCard(title: "Calls", value: String(records.calls.count), symbol: "phone", footnote: "Synthetic records")
                SummaryCard(title: "Device state", value: deviceStatus(device.id), symbol: "externaldrive", footnote: "Isolated local store", compact: true)
            }

            HStack(alignment: .top, spacing: 20) {
                history(for: records)
                    .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                queue
                    .frame(width: 280)
                    .frame(minHeight: 0, maxHeight: .infinity)
            }
            .frame(minHeight: 0, maxHeight: .infinity)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
    }

    private func history(for records: DeviceRecords) -> some View {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let messages = records.messages.filter {
            search.isEmpty || $0.contact.localizedCaseInsensitiveContains(search) || $0.body.localizedCaseInsensitiveContains(search)
        }.sorted { $0.timestamp > $1.timestamp }
        let calls = records.calls.filter {
            search.isEmpty || $0.contact.localizedCaseInsensitiveContains(search) || $0.direction.localizedCaseInsensitiveContains(search)
        }.sorted { $0.timestamp > $1.timestamp }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Local history").font(.headline)
                Spacer()
                Picker("History type", selection: $selectedHistory) {
                    ForEach(HistoryKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)
            }
            .padding(16)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(selectedHistory == .messages ? "Search contact or message" : "Search contact or direction", text: $query)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search synthetic history for the selected device")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Clear search")
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
            Divider()
            if selectedHistory == .messages {
                if messages.isEmpty {
                    historyEmpty(isSearching: !search.isEmpty)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(messages, id: \.id) { message in
                                MessageRow(message: message)
                                Divider().padding(.leading, 56)
                            }
                        }
                    }
                }
            } else {
                if calls.isEmpty {
                    historyEmpty(isSearching: !search.isEmpty)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(calls, id: \.id) { call in
                                CallRow(call: call)
                                Divider().padding(.leading, 56)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
    }

    private func historyEmpty(isSearching: Bool) -> some View {
        ContentUnavailableView(
            isSearching ? "No matching demo records" : "No synthetic records yet",
            systemImage: isSearching ? "magnifyingglass" : "tray",
            description: Text(isSearching ? "Try another search for this device." : "The queue will populate this view when a fixture completes.")
        )
        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }

    private var queue: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sync queue").font(.headline)
                Spacer()
                Text("\(controller.jobs.count)")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
            HStack(spacing: 6) {
                Circle().fill(controller.lastError != nil ? Color.orange : controller.isRunning ? Color.teal : Color.secondary).frame(width: 6, height: 6)
                Text(controller.lastError != nil ? "Storage needs attention" : controller.isRunning ? "Processing one job at a time" : "Queue is idle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                perform { try controller.interruptActive() }
            } label: {
                Label("Interrupt active job", systemImage: "pause.circle")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!controller.jobs.contains(where: { $0.state == .running }))
            .help("Stop the active synthetic job; use Retry to start another attempt")
            if let error = controller.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(controller.jobs.reversed(), id: \.id) { job in
                        QueueJobCard(job: job) { perform { try controller.retry(job.id) } }
                    }
                    if controller.jobs.isEmpty {
                        Text("Imported fixtures appear here.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 24)
                    }
                }
                .padding(.vertical, 2)
            }
            Text("All devices share one serialized queue. Interrupted work requires an explicit retry.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.07)))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "internaldrive")
            Text("Local synthetic JSON • Unencrypted prototype storage • No accounts or cloud services")
            Spacer(minLength: 0)
            Text("ARM64 · SwiftUI").foregroundStyle(.tertiary)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func deviceStatus(_ id: UUID) -> String {
        let jobs = controller.jobs.filter { $0.deviceID == id }
        if jobs.contains(where: { $0.state == .running }) { return controller.isRunning ? "Processing" : "Stopped" }
        if jobs.contains(where: { $0.state == .queued }) { return "Queued" }
        if jobs.contains(where: { $0.state == .failed || $0.state == .interrupted }) { return "Needs retry" }
        if controller.records(for: id).updatedAt != nil { return "Demo ready" }
        return "Awaiting fixture"
    }

    private func deviceActivityColor(_ id: UUID) -> Color {
        switch deviceStatus(id) {
        case "Processing", "Demo ready": return .teal
        case "Needs retry", "Stopped": return .orange
        default: return .secondary
        }
    }

    private func enqueue(device: DemoDevice, fault: DemoFault) {
        guard let key = DemoDeviceKey(id: device.id) else { return }
        perform { try controller.enqueue(DemoFixture(device: key, scenario: .refresh), fault: fault) }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { actionError = error.localizedDescription }
    }
}

private enum HistoryKind: String, CaseIterable, Identifiable {
    case messages = "Messages"
    case calls = "Calls"
    var id: Self { self }
}
