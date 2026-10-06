# DeviceBridge roadmap

6 October 2026. See the [specification](specification.md) for scope and source-backed availability limits, and the [README](../README.md) for verified commands and results. Checkboxes are acceptance gates, not dates or promised device support. Complete an item only with supporting evidence.

## Milestone 0 — Synthetic native prototype

- [x] Define an independent, consent-based product with synthetic-only first-milestone boundaries.
- [x] Document data flow, per-device isolation, restart behavior, privacy limits, and future dependency review.
- [x] Build the SwiftUI app and Swift harness with the installed Apple toolchain and at most two SwiftPM jobs.
- [x] Verify every delivered executable is arm64 and requires no Electron or Rosetta component.
- [x] Show two clearly fictional devices, status, isolated calls/messages, and per-device search under persistent **Synthetic Demo** labeling.
- [x] Import bounded enum-only fixture descriptors; reject free-text record payloads, unknown choices, malformed data, and unsupported versions before mutation.
- [x] Persist one serialized queue and device-scoped records; demonstrate success, visible failure, interruption, and explicit retry.
- [x] Recover saved running work as interrupted after restart; repeat the same fixture without duplicate history.
- [x] Test fixture boundaries, device isolation, serial execution, failure/retry, and recovery with temporary demo storage.
- [x] Run the local harness and launch-check the native interface; record exact evidence and limitations in the verification log.
- [x] Create the separate local repository and initial commit; keep generated data/build outputs out of Git. Remote publication requires a separately approved destination.

## Milestone 1 — Review gates before private data

No real pairing, backup, password, or private history is allowed until these gates are completed and that work is separately authorized.

- [ ] Review a consent flow for adult participants, each device, each data category, retention, pause, revocation, and deletion.
- [ ] Threat-model local storage, parser boundaries, logs, helper processes, credentials, cross-device isolation, and backups of the Mac itself.
- [ ] Pin and review upstream `libimobiledevice` and each dependency; decide license-compliant linkage/distribution, required notices/source materials, and update policy.
- [ ] Produce and inspect arm64 builds of every selected upstream component using upstream source; never reuse Qustodio packages or assets.
- [ ] Implement and test a Keychain secret provider and authenticated encrypted store, including key lifecycle and failure recovery. Interfaces or TODOs alone do not complete this item.
- [ ] Define process ownership, storage locking, transactional writes, corruption handling, disk-space limits, and recovery; test beyond single-file atomic replacement.
- [ ] Review application sandboxing, signing, notarization, minimal entitlements, and dependency provenance for the intended distribution method.

## Milestone 2 — Consented USB proof of concept

- [ ] Enroll a separately authorized test device through a visible USB/on-device Trust flow; show verified device identity and acquisition scope.
- [ ] Add a transport adapter behind the existing queue/storage boundaries, with one active acquisition across devices initially.
- [ ] Acquire only explicitly approved local backup data; do not access credentials, existing private backups, or unrelated devices automatically.
- [ ] Parse a documented supported backup schema into a staging store; commit only validated records to the correct device namespace.
- [ ] Report backup timestamp, source, available categories, unsupported data, and iCloud-related omissions without promising complete history.
- [ ] Test disconnect, lock, trust revocation, wrong backup password, insufficient disk space, schema changes, cancellation, crash recovery, and duplicate import.
- [ ] Demonstrate pause/revoke/deletion and ensure revocation prevents queued or active reacquisition.

## Milestone 3 — Multiple trusted devices and Wi-Fi

- [ ] Establish a tested compatibility matrix for macOS, iOS/iPadOS, device models, encryption, and supported record types.
- [ ] Prove cross-device credential, backup, normalized-history, and search-index isolation with multiple authorized devices.
- [ ] Offer optional Wi-Fi only after USB enrollment succeeds; revalidate identity and trust, and show unreachable/locked states accurately.
- [ ] Make local retry policy bounded, observable, and cancelable. Recheck consent before acquisition and stop on revocation.
- [ ] Define foreground availability first; add any scheduling or launch service only as an explicit later feature with clear sleep/offline behavior.
- [ ] Validate sustained resource use, large-history search, retention, corruption recovery, and interrupted multi-device jobs on Apple silicon.

## Milestone 4 — Release readiness

- [ ] Complete privacy/security review and independent verification of implemented controls.
- [ ] Verify all distributed executable architectures, signing, notarization, dependency obligations, and update rollback.
- [ ] Document supported configurations and measured limitations; state that backups may omit records and cannot establish complete activity history.
- [ ] Test export/deletion/retention behavior, accessibility, and failure guidance using approved data only.
- [ ] Choose any remote repository or release destination with the user before publishing. Cloud accounts, cloud sync, and account creation are outside the present roadmap.

## Recovery while development is interrupted

Keep specification, source, fixtures, and reproducible commands in local Git. Keep private data and build outputs out of commits. Stop work when the host is unavailable; continue after it returns. An atomic queue snapshot improves recoverability but does not prove persistence through hardware power loss. Reopen the app, inspect interrupted work, and retry explicitly; no unattended background execution is implied.
