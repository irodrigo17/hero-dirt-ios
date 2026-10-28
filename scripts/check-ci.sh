#!/usr/bin/env bash
# The same complete preflight runs locally and in GitHub Actions.
set -euo pipefail

# Keep a long local UI run from being suspended by idle system sleep. The
# assertion ends with this script, including when the parent is terminated.
if [[ "$(uname -s)" == "Darwin" ]] && command -v caffeinate >/dev/null 2>&1; then
  caffeinate -i -w "$$" &
  wake_assertion_pid=$!
  trap 'kill "$wake_assertion_pid" 2>/dev/null || true' EXIT
fi

cd "$(dirname "${BASH_SOURCE[0]}")/.."
output_dir="${CI_OUTPUT_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/herodirt-ci.XXXXXX")}"
derived_data="${CI_DERIVED_DATA_PATH:-$output_dir/HeroDirtBuild}"
result_bundle="${CI_RESULT_BUNDLE_PATH:-$output_dir/HeroDirtTests.xcresult}"
mkdir -p "$output_dir" "$(dirname "$result_bundle")"
if [[ -e "$result_bundle" ]]; then
  echo "Result bundle already exists: $result_bundle. Choose a fresh CI_OUTPUT_DIR or CI_RESULT_BUNDLE_PATH." >&2
  exit 1
fi

python3 scripts/check-localizations.py
xcodebuild -version
if [[ -n "${SIMULATOR_UDID:-}" ]]; then
  simulator="$SIMULATOR_UDID"
else
  simulator="$(python3 - <<'PY'
import json
import subprocess
import sys

runtimes = json.loads(subprocess.check_output(
    ["xcrun", "simctl", "list", "devices", "available", "--json"], text=True
))["devices"]
candidates = []
for runtime, devices in runtimes.items():
    if ".iOS-" not in runtime:
        continue
    version = tuple(int(part) for part in runtime.split(".iOS-", 1)[1].split("-"))
    if version < (26, 0):
        continue
    for device in devices:
        if device["isAvailable"] and device["name"].startswith("iPhone"):
            candidates.append((version, device["name"] == "iPhone 17 Pro", device["name"], device["udid"]))
if not candidates:
    raise SystemExit("No available iPhone simulator with iOS 26 or later")
version, _, name, udid = max(candidates)
print(f"Using {name}, iOS {'.'.join(map(str, version))} ({udid})", file=sys.stderr)
print(udid)
PY
)"
fi

echo "Simulator: $simulator"
echo "Build and test diagnostics: $output_dir"
# Ad-hoc signing supplies the simulator app's required iCloud entitlements.
xcodebuild build-for-testing \
  -project HeroDirt.xcodeproj -scheme HeroDirt \
  -destination "platform=iOS Simulator,id=$simulator" \
  -derivedDataPath "$derived_data" \
  CODE_SIGN_IDENTITY=- \
  2>&1 | tee "$output_dir/build.log"
xcodebuild test-without-building \
  -project HeroDirt.xcodeproj -scheme HeroDirt \
  -destination "platform=iOS Simulator,id=$simulator" \
  -derivedDataPath "$derived_data" \
  -parallel-testing-enabled NO \
  -resultBundlePath "$result_bundle" \
  2>&1 | tee "$output_dir/test.log"
