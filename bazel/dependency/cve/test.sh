#!/usr/bin/env bash
set -euo pipefail

f=bazel_tools/tools/bash/runfiles/runfiles.bash
# shellcheck disable=SC1090
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null ||
    source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null ||
    source "$0.runfiles/$f" 2>/dev/null ||
    { echo >&2 "ERROR: cannot find runfiles.bash"; exit 1; }

JQ_BIN="$(rlocation "$JQ_BIN")"
JQ_REPORT="$(rlocation "$JQ_REPORT")"
SCANNED="$(rlocation "$SCANNED")"
CVES_PENDING="$(rlocation "$CVES_PENDING")"

# Matches pending NVD analysis (CNA-asserted only) fail the test only with
# `pending: error` in the config, otherwise they are reported as a warning
# (`skip` does not scan for them at all).
pending="$("$JQ_BIN" -r '.' "$CVES_PENDING")"
if [[ "$pending" != "warn" && "$pending" != "error" && "$pending" != "skip" ]]; then
    echo >&2 "Expected \`pending\` to be \`warn\`, \`error\` or \`skip\`, got: $pending"
    exit 2
fi

total="$("$JQ_BIN" 'length' "$SCANNED")"
if [[ "$total" -eq 0 ]]; then
    exit 0
fi
"$JQ_BIN" -r -f "$JQ_REPORT" "$SCANNED"
analyzed="$("$JQ_BIN" '[.[] | select(.status != "pending")] | length' "$SCANNED")"
if [[ "$analyzed" -gt 0 || "$pending" == "error" ]]; then
    exit 1
fi
echo
echo "WARNING: only matches pending NVD analysis were found (set \`pending: error\` to fail on these)"
