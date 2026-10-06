#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
[[ "$(uname -m)" == arm64 ]] || { print -u2 'Run natively on Apple Silicon.'; exit 1; }
xcrun swift test --arch arm64 --jobs 2
bin_dir="$(xcrun swift build --arch arm64 --show-bin-path)"
for executable in DeviceBridge devicebridge-fixtures; do
  [[ "$(lipo -archs "$bin_dir/$executable")" == arm64 ]]
  file "$bin_dir/$executable"
done
scratch="$(mktemp -d "${TMPDIR:-/tmp/}devicebridge-verify.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
harness="$bin_dir/devicebridge-fixtures"
"$harness" seed --store "$scratch/demo"
"$harness" import --store "$scratch/demo" --fixture Fixtures/aurora-refresh.json
"$harness" failure-demo --store "$scratch/demo"
"$harness" interrupt-demo --store "$scratch/demo"
"$harness" checkpoint-interruption --store "$scratch/recovery"
recovered="$("$harness" status --store "$scratch/recovery")"
print -r -- "$recovered"
[[ "$recovered" == *'| interrupted |'* ]]
print 'PASS: unit tests, arm64 executables, fixture import, failure/retry, interruption/retry, and process-exit recovery.'
