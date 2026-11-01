#!/usr/bin/env bash
set -euo pipefail

f=bazel_tools/tools/bash/runfiles/runfiles.bash
# shellcheck disable=SC1090
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null ||
    source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null ||
    { echo >&2 "ERROR: cannot find runfiles.bash"; exit 1; }

# Only pending (CNA-asserted) matches: the outcome depends on `pending` in the config.
status=0
"$(rlocation "$CVE_TEST")" > "$TEST_TMPDIR/report" 2>&1 || status=$?
[[ "$status" -eq "$EXPECTED_STATUS" ]]
grep -q "CVE-2024-0006" "$TEST_TMPDIR/report"
grep -q "Pending NVD analysis" "$TEST_TMPDIR/report"
grep -q "1 potential CVE vulnerabilities found" "$TEST_TMPDIR/report"
if [[ "$EXPECTED_STATUS" -eq 0 ]]; then
    grep -q "WARNING: only matches pending NVD analysis were found" "$TEST_TMPDIR/report"
else
    if grep -q "WARNING" "$TEST_TMPDIR/report"; then
        exit 1
    fi
fi
