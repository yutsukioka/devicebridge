# DeviceBridge

A native Apple Silicon macOS prototype for an independent, consent-based, multi-device calls/messages backup viewer. **Version 0.1 is a Synthetic Demo:** it has no device connection, pairing, backup, account, credential, network, or cloud functionality. Every visible contact and conversation is fictional.

The SwiftUI app provides two demo devices, isolated local histories, search, a serialized import queue, visible progress, simulated failure, interruption, and explicit retry. Strict JSON fixtures choose built-in scenarios; importing arbitrary call/message content is unsupported.

## Build and run

Requires an Apple Silicon Mac, macOS 14 or newer, and an installed Apple Swift 6 toolchain (Xcode or compatible command-line tools). There are no third-party package dependencies. This prototype was developed using Swift 6.4 on macOS 27.0.1; older supported deployment versions have not been tested.

```sh
cd /Users/yutsukioka2/git/devicebridge
./scripts/verify.sh
./scripts/build-app.sh
open artifacts/DeviceBridge.app
```

The build script limits SwiftPM to two jobs, explicitly targets `arm64`, checks the resulting architecture, and creates a locally ad-hoc signed `.app`. This is not a notarized distributable or an App Sandbox implementation. The source also rejects non-arm64 compilation.

To run directly during development:

```sh
xcrun swift run --arch arm64 --jobs 2 DeviceBridge
```

The app seeds both fictional devices on first use. Select a device, switch between calls and messages, and use search. Queue controls let you import another scenario, interrupt an active job, simulate a failure, and retry a failed or interrupted job. The fixture picker accepts only the JSON schema below.

## Fixture harness

Use a dedicated demo directory; the command-line harness always requires an explicit storage location. Avoid pointing it at folders containing other work. The app and harness reject simultaneous access to the same store.

```sh
xcrun swift run --arch arm64 --jobs 2 devicebridge-fixtures seed --store /tmp/devicebridge-example
xcrun swift run --arch arm64 --jobs 2 devicebridge-fixtures import --store /tmp/devicebridge-example --fixture Fixtures/aurora-refresh.json
xcrun swift run --arch arm64 --jobs 2 devicebridge-fixtures failure-demo --store /tmp/devicebridge-example
xcrun swift run --arch arm64 --jobs 2 devicebridge-fixtures interrupt-demo --store /tmp/devicebridge-example
xcrun swift run --arch arm64 --jobs 2 devicebridge-fixtures checkpoint-interruption --store /tmp/devicebridge-recovery
xcrun swift run --arch arm64 --jobs 2 devicebridge-fixtures status --store /tmp/devicebridge-recovery
```

`checkpoint-interruption` intentionally exits after persisting a running job. The next `status` invocation recovers it as interrupted; it does not silently resume. Retry it through the UI using the same store:

```sh
open artifacts/DeviceBridge.app --args --store-root /tmp/devicebridge-recovery
```

An exact fixture example:

```json
{"schemaVersion":1,"syntheticDemo":true,"device":"aurora","scenario":"baseline"}
```

Only `aurora` and `borealis`, and `baseline` and `refresh`, are accepted. Unknown fields, unsupported schema versions, non-demo markers, and oversized fixture files are rejected. The schema has no phone-number, contact-name, or message-body input fields. A refresh replaces that device's deterministic snapshot; repeating an import does not duplicate records.

## Storage and recovery

The default UI store is a dedicated `DeviceBridge/SyntheticDemo` directory under the current user's Application Support folder. `--store-root PATH` selects an alternative dedicated directory. Demo records are stored separately per device, while a shared queue persists jobs and their states. A process lock prevents simultaneous cooperating writers. On launch, saved queued/running jobs become interrupted and wait for explicit retry. Completed snapshots remain readable. A retry replaces the selected device snapshot; other devices' histories remain separate.

**Demo storage is plaintext.** Encryption, Keychain integration, independently verified consent, production file hardening, retention controls, sandboxing, and a security audit remain future work. Atomic file replacement and process-exit recovery tests do not prove physical power-loss durability. Work runs only while the app or harness is running and the host is available; no background service or unattended sync is installed.

## Verification

On 6 October 2026, all 13 automated tests and the fixture/recovery harness passed. The release app and harness were verified as arm64; the native interface was launch-checked, including device-scoped search and the default window layout. See [exact commands, results, and limits](docs/verification.md).

## Project map

- `Sources/DeviceBridgeCore`: typed fictional scenarios, storage abstraction, durable queue and records.
- `Sources/DeviceBridgeApp`: native SwiftUI macOS views.
- `Sources/DeviceBridgeFixtures`: arm64 fixture and recovery harness.
- `Tests/DeviceBridgeCoreTests`: isolation, idempotence, serialized execution, failure/retry, interruption, persistence and import validation.
- `Fixtures`: strict example scenario JSON files.
- [Specification](docs/specification.md): data flow, consent/security requirements and availability limits.
- [Roadmap](docs/roadmap.md): prototype acceptance and gated USB/Wi-Fi work.
- [Verification](docs/verification.md): exact commands, environment, results and remaining gaps.

No Qustodio binaries, code, or assets are included or reused. No upstream device libraries are embedded in this milestone. Any future libimobiledevice integration requires pinned source, component-level license review, native arm64 builds, consent design, and explicit scope approval. This repository is local only; no remote publication is configured.
