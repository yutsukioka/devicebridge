# Verification log

Checked 6 October 2026 in `/Users/yutsukioka2/git/devicebridge`.

## Environment

- Native Apple Silicon `arm64`, macOS 27.0.1 (26A434).
- Apple Swift 6.4 (`swiftlang-6.4.0.34.1`, `clang-2100.3.34.1`).
- Developer directory: `/Applications/Xcode.app/Contents/Developer`.
- Swift tools version 6.0; deployment target macOS 14. Earlier macOS releases were not tested.
- No third-party dependencies installed or embedded. No network or real-device operations in the prototype.

## Automated verification

Exact command:

```sh
cd /Users/yutsukioka2/git/devicebridge
./scripts/verify.sh
```

Result: **PASS**, exit status 0. `swift test --arch arm64 --jobs 2` built successfully and ran **13 XCTest tests, 0 failures**, in 12.167 seconds. The subsequent Swift Testing runner reports zero additional tests; this does not replace the 13 XCTest results. Full generated output is in `artifacts/verification.log` (ignored by Git).

Covered behaviors:

- Completed records survive reopening; concurrent access to one store is rejected.
- Corrupt queue contents are reported and preserved.
- Cross-device snapshot writes are rejected; imports do not change another device's records.
- Reimporting deterministic fixtures preserves record IDs without duplication.
- The queue never runs two jobs together; a failed job does not stop an independent queued job.
- Simulated failure and interruption require explicit retry and expose attempt counts.
- Strict fixture parsing rejects unsupported versions, non-demo markers, unknown fields/choices, malformed and oversized input.
- FIFO inputs are rejected without blocking for both fixtures and stored queue files.
- A recoverable storage write failure saves an interrupted state. If that recovery write also fails, further mutations are blocked with restart guidance.
- Restart converts both queued and running checkpoints to interrupted without starting work.

The script additionally invoked the native harness against fresh temporary stores:

```sh
devicebridge-fixtures seed --store TEMP/demo
devicebridge-fixtures import --store TEMP/demo --fixture Fixtures/aurora-refresh.json
devicebridge-fixtures failure-demo --store TEMP/demo
devicebridge-fixtures interrupt-demo --store TEMP/demo
devicebridge-fixtures checkpoint-interruption --store TEMP/recovery
devicebridge-fixtures status --store TEMP/recovery
```

Observed: baseline gives each device 3 fictional calls and 4 fictional messages. Refresh gives Aurora 4 calls and 5 messages while Borealis stays at 3/4. Failure and interruption retries finish at attempt 2. Abrupt process exit leaves a saved running checkpoint; the next process reports it as interrupted, with no automatic record import. The script creates and removes its own temporary directories; `TEMP` above represents that generated path.

## Release and architecture

```sh
./scripts/build-app.sh
file artifacts/DeviceBridge.app/Contents/MacOS/DeviceBridge \
  .build/out/Products/Release/devicebridge-fixtures \
  .build/out/Products/Debug/DeviceBridgeCoreTests.xctest/Contents/MacOS/DeviceBridgeCoreTests
codesign --verify --strict --verbose=2 artifacts/DeviceBridge.app
```

Result: release build succeeded; app and harness are **Mach-O 64-bit executable arm64**, test bundle is **Mach-O 64-bit bundle arm64**. `lipo -archs` also reports only `arm64` for the app and both debug products. The local ad-hoc signature verifies (`valid on disk`, `satisfies its Designated Requirement`). This is not Developer ID signing, notarization, App Sandbox, or a production security review. Build output is in `artifacts/build-app.log`.

## Native interface check

```sh
open artifacts/DeviceBridge.app --args \
  --store-root /Users/yutsukioka2/git/devicebridge/artifacts/ui-smoke-store
```

The app launched and automatically completed both baseline fixtures in the isolated smoke-test store. Accessibility and screenshot inspection confirmed the synthetic label, device statuses, record counts and queue outcomes. Searching Aurora for `observatory` narrowed the messages to one fictional record. Searching `Alex` and selecting Borealis showed no matching records. Clearing search and selecting Calls showed Borealis's Taylor/Casey fictional calls, with directions and durations.

A default-window clipping issue found during visual review was corrected by constraining the window and split-view columns to their available geometry and allowing the history/queue panels to shrink and scroll. The release app was rebuilt successfully after this UI-only change (final incremental build: 3.54 seconds). A second screenshot inspection at the default 1260 × 820 window size confirmed the banner, title, device list, scrollable history/queue, sidebar disclosure, and bottom storage disclaimer remain visible. The core sources and tests did not change after the passing automated run.

## Scope and remaining validation

- Synthetic-only: no actual USB or Wi-Fi connection, device trust, pairing, backups, credentials, private calls/messages, Qustodio access, cloud integration, accounts, or telemetry.
- Storage is plaintext fictional JSON; no encryption or Keychain implementation. Advisory locking and file checks are not a hostile-user filesystem sandbox.
- Process-exit recovery and atomic replacement were tested; physical power-loss durability was not. Queue and records are separate file commits. Retry is idempotent if a crash happens between them.
- No automated GUI test suite, older-macOS compatibility run, large-data benchmark, physical-device integration test, accessibility audit, or production security audit is claimed.
- Work requires the host and process to be available. No launch agent or scheduled background service was installed.

## Build-environment notes and resumption

Initial staging was under `/Users/yutsukioka2/Documents/Codex/2026-10-06/task-4/DeviceBridge`. The restricted executor could not write the default compiler cache or run SwiftPM's nested manifest sandbox. The authorized build was then run with execution access appropriate for Apple tooling. File Provider metadata in the Documents staging folder subsequently blocked test-bundle signing. Building in the requested Git directory resolved that issue; no security settings were disabled or dependencies installed.

The separate local repository was initialized once after confirming no file/directory/symlink collision. The initial local commit contains source, fixtures, scripts, specification, roadmap, and this verification record; generated builds, logs, and demo stores are ignored. No remote was created or configured. No commands modified `un_job_application_helper` or Qustodio.

After an interrupted development session, inspect this repository and its Git status, preserve existing changes, and run the scripts here with at most two build jobs. Do not initialize another repository or publish remotely. Runtime interrupted jobs require explicit retry when the host is available.
