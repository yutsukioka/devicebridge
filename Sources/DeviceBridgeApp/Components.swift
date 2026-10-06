import DeviceBridgeCore
import SwiftUI

struct SummaryCard: View {
    let title: String
    let value: String
    let symbol: String
    let footnote: String
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: symbol).foregroundStyle(.teal)
            }
            Text(value)
                .font(.system(size: compact ? 22 : 29, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .monospacedDigit()
            Text(footnote).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
    }
}

struct MessageRow: View {
    let message: MessageRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RecordGlyph(symbol: isOutgoing ? "arrow.up.right" : "arrow.down.left", color: .teal)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(message.contact).font(.callout.weight(.semibold))
                    Spacer(minLength: 10)
                    Text(message.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(message.body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Text("\(message.direction.capitalized) · Synthetic message")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
    }

    private var isOutgoing: Bool {
        message.direction.lowercased().contains("out") || message.direction.lowercased().contains("sent")
    }
}

struct CallRow: View {
    let call: CallRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RecordGlyph(symbol: "phone", color: call.durationSeconds == 0 ? .orange : .blue)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(call.contact).font(.callout.weight(.semibold))
                    Spacer(minLength: 10)
                    Text(call.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text(call.direction.capitalized)
                    Text("·")
                    Text(duration)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                Text("Synthetic call").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(16)
    }

    private var duration: String {
        guard call.durationSeconds > 0 else { return "No connected duration" }
        let minutes = call.durationSeconds / 60
        let seconds = call.durationSeconds % 60
        return minutes == 0 ? "\(seconds) sec" : "\(minutes) min \(seconds) sec"
    }
}

private struct RecordGlyph: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(color)
            .frame(width: 30, height: 30)
            .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
            .accessibilityHidden(true)
    }
}

struct QueueJobCard: View {
    let job: SyncJob
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(stateLabel, systemImage: stateSymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(stateColor)
                Spacer()
                Text("Attempt \(job.attempt)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(job.deviceName)
                .font(.callout.weight(.medium))
                .lineLimit(2)
            ProgressView(value: min(max(job.progress, 0), 1))
                .tint(stateColor)
                .accessibilityLabel("\(job.deviceName) fixture progress")
            Text(job.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if job.state == .failed || job.state == .interrupted {
                Button(action: retry) {
                    Label("Retry fixture", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .help("Retry this job as a new attempt in the serialized queue")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(stateColor.opacity(job.state == .failed || job.state == .interrupted ? 0.3 : 0.09)))
    }

    private var stateLabel: String {
        switch job.state {
        case .queued: return "Queued"
        case .running: return "Running"
        case .interrupted: return "Interrupted"
        case .failed: return "Failed"
        case .completed: return "Completed"
        }
    }

    private var stateColor: Color {
        switch job.state {
        case .running, .completed: return .teal
        case .failed, .interrupted: return .orange
        case .queued: return .secondary
        }
    }

    private var stateSymbol: String {
        switch job.state {
        case .queued: return "clock"
        case .running: return "arrow.triangle.2.circlepath"
        case .interrupted: return "pause.circle"
        case .failed: return "exclamationmark.circle"
        case .completed: return "checkmark.circle.fill"
        }
    }
}

struct DemoAboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 5) {
                    Text("DeviceBridge").font(.title.bold())
                    Text("Independent native macOS prototype")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("SYNTHETIC DEMO")
                    .font(.caption2.bold())
                    .foregroundStyle(.teal)
                    .padding(8)
                    .background(Color.teal.opacity(0.1), in: Capsule())
            }
            Divider()
            AboutSection(title: "What this prototype does", symbol: "testtube.2") {
                Text("Browse fictional calls and messages, search each device’s records, import bounded synthetic fixture JSON, and exercise a serialized job queue with interruptions and retries. An empty store starts with two fictional devices and two demo jobs.")
            }
            AboutSection(title: "Try the workflow", symbol: "play.circle") {
                Text("Choose a device, then use Run demo to queue a refresh or simulate one failed attempt. Use Interrupt active job while work is running, or Retry fixture after a failure or interruption. Queue history and per-device records persist locally between launches.")
            }
            AboutSection(title: "Storage and privacy limits", symbol: "externaldrive") {
                Text("Only built-in fictional records are supported. Prototype records are unencrypted local JSON. Keychain integration, data encryption, sandboxing, code signing, and consent verification are not implemented security guarantees.")
            }
            AboutSection(title: "Future device support", symbol: "cable.connector") {
                Text("There is no device discovery, pairing, backup extraction, live sync, account, or cloud integration. Future USB Trust and Wi-Fi work requires explicit device-owner consent, availability testing, and an upstream library license review. This app does not use Qustodio binaries, assets, credentials, or private APIs.")
            }
            HStack {
                Text("SwiftUI • macOS 14 or later • Apple silicon")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 660)
    }
}

private struct AboutSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.teal)
                .frame(width: 22)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                content
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
