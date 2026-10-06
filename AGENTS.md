# DeviceBridge engineering rules

- Work only inside this repository. Do not change other applications or repositories.
- This milestone is synthetic-only. No real device access, pairing, backup parsing, credentials, network calls, private APIs, telemetry, or cloud services.
- Use Swift/SwiftUI and the installed Apple toolchain. Every delivered executable must be arm64; no Electron or Rosetta dependency.
- Keep per-device records isolated, fixture imports bounded and deterministic, and queue transitions durable and observable. On restart, report interrupted work and require an explicit retry.
- Do not describe Keychain, encryption, sandboxing, signing or consent verification as implemented unless tested.
- Build/test with at most two SwiftPM jobs. Keep generated data and build artifacts out of Git.
- No remote creation, upload or push without an explicit destination approved by the user.
