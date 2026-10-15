# Issue #1 local verification and repairs

Checked 14 October 2026 against `1d3e2bd381a054573f660c543c350546c0d959c3`. Both the original checkout HEAD and GitHub `main` (read-only branch lookup) matched that revision. Issue: https://github.com/yutsukioka/devicebridge/issues/1.

Work is isolated in a local clone on `fix/issue-1-local`. The original checkout's untracked `.vscode/` directory was preserved. All runtime stores were newly created disposable directories containing generated fictional records; even harness `status` was restricted to these directories because it can persist recovery state.

## Candidate dispositions

| Candidate | Result |
| --- | --- |
| `waitUntilIdle` and future enqueue paths | No present defect. The controller is main-actor isolated, the worker clears itself without a suspension at drain completion, and the waiter rechecks the current worker. Added a passing regression for enqueue while an existing waiter is suspended. No production change. |
| Intermediate-directory symlink redirection | Confirmed current impact. Renaming an open store root or its ancestor and replacing it with a symlink redirected reads and writes into a second store even while that store held its own lock. Fixed by retaining the root descriptor, locking relative to it, opening each child directory with `O_DIRECTORY` and `O_NOFOLLOW`, and using descriptor-relative read/create/rename/unlink operations. |
| Orphaned atomic-write temporary files | Confirmed. A controlled abrupt process exit before the atomic rename left one temporary file that survived reopening. Startup now sweeps only exact writer-generated regular-file names, in the root and known device directories, after acquiring the writer lock. |
| Misleading storage-fault guard after healthy restart | Reported premise is unreachable. Initialization converts every queued/running checkpoint to interrupted and saves recovery before returning, or throws. Added a regression proving a healthy recovered running checkpoint permits new work and explicit retry. No production change. |
| Dropped unknown device IDs | No reachable current UI input. Devices are private-set and constructed from the exhaustive built-in enum; selection uses that list, and imported fixtures decode the enum. No production change. |
| Unused published revision | No demonstrated defect. Besides being cosmetic at most, the published property emits observation notifications after private records change. No production change. |

A related current storage defect was also reproduced and fixed: a dangling `queue.json` or `records.json` symlink was treated as absent by the old `fileExists` preflight. Reads now open without following links and return empty state only for an actually missing path; symlinks are reported and preserved.

## Verification

Installed Apple Swift 6.4 on native arm64 macOS; deployment target macOS 14. No dependencies or software were installed. SwiftPM used at most two jobs, with scratch and compiler cache directories under `/tmp`. The per-command `--disable-sandbox` flag avoids SwiftPM's nested manifest sandbox in the restricted executor; no system security settings changed.

Exact test command, from the isolated checkout:

```sh
env CLANG_MODULE_CACHE_PATH=/tmp/devicebridge-issue1-baseline-build/module-cache \
  SWIFTPM_MODULECACHE_OVERRIDE=/tmp/devicebridge-issue1-baseline-build/module-cache \
  xcrun swift test --disable-sandbox --arch arm64 --jobs 2 \
  --scratch-path /tmp/devicebridge-issue1-baseline-build \
  --cache-path /tmp/devicebridge-issue1-baseline-build/cache \
  --config-path /tmp/devicebridge-issue1-baseline-build/config \
  --security-path /tmp/devicebridge-issue1-baseline-build/security
```

- Original source: **13 XCTest tests, zero failures** (12.425 seconds). Independently invoking the built bundle with `xcrun xctest` also passed all 13.
- New tests against original production source: **24 tests, 11 failed assertions across five tests**. Failures demonstrated retained temporary files, queue/snapshot redirection and dangling-symlink empty state. Original tests, queue candidate checks and static child-symlink controls passed.
- Patched source: **24 XCTest tests, zero failures** (13.225 seconds). The separate Swift Testing runner has no additional tests.
- Fixture harness: `seed`, `import` with `Fixtures/aurora-refresh.json`, `failure-demo`, `interrupt-demo`, `checkpoint-interruption`, and subsequent `status` all passed in freshly generated temporary stores. Aurora refresh left Borealis isolated; failure/interruption retries completed on attempt 2; restart recovered the abandoned running checkpoint as interrupted.
- Atomic crash reproduction: a small test-only arm64 interposer, compiled with installed Clang, exited the disposable harness process at temporary-file `fsync`, before rename. Baseline: exit 86, one leftover before restart and one after. Patched: exit 86, one before and zero after; restart succeeded. Injection was scoped to that one child process through its environment.
- `file` and `lipo -archs` confirmed the app, harness and XCTest bundle are arm64.
- `git diff --check` passed.

Generated evidence is ignored under `artifacts/`: `baseline-tests.log`, `baseline-xctest.log`, `regression-build-before.log`, `baseline-crash-reproduction.log`, `patched-tests.log`, `patched-harness.log`, and the test-only `crash-before-rename.c`/`.dylib`.

## Independent review and limits

A separate reviewer inspected the final storage/test diff, descriptor ownership, error cleanup, lock ordering, bounded reads and the before/after test evidence. No actionable regressions or review blockers were found. The reviewer did not rerun the builds concurrently.

The path-redirection reproductions are deterministic root/ancestor replacements between storage calls. Child-directory tests cover static replacement; a forced swap between individual syscalls was not dynamically exercised. Descriptor-relative component traversal addresses that remaining race by inspection.

Root ancestors must be trusted at initial open. This is still advisory locking for cooperating writers, not a sandbox against a process that can directly modify the store or replace its lock. Cleanup deliberately ignores unrecognized names and non-regular entries. Physical power loss, real ENOSPC, older macOS versions and GUI behavior were not newly tested. Existing injected storage-failure tests passed. Queue and snapshot commits remain separate, with explicit idempotent retry.

## Prepublication revalidation — 15 October 2026

GitHub `main` still points to the reviewed base revision; issue #1 remains unchanged with zero comments. The seven-file patch matched the previously reviewed patch byte for byte before this documentation refresh. A second independent inspection confirmed that review remains valid and found no credentials, private content, generated stores, logs or binaries among the proposed files.

The same two-job arm64 Swift command passed **24 XCTest tests, zero failures** again (12.963 seconds). The complete disposable fixture/recovery harness and abrupt atomic-write crash cleanup also passed again; products remain arm64. Fresh output is retained locally in ignored `artifacts/prepublication-tests.log` and `artifacts/prepublication-harness.log`.
