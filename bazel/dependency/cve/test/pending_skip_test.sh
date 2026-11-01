#!/usr/bin/env bash
set -euo pipefail

f=bazel_tools/tools/bash/runfiles/runfiles.bash
# shellcheck disable=SC1090
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null ||
    source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null ||
    { echo >&2 "ERROR: cannot find runfiles.bash"; exit 1; }

JQ_BIN="$(rlocation "$JQ_BIN")"
SCANNED="$(rlocation "$SCANNED")"

# `pending: skip`: NVD matches only, no CNA pass
[[ "$("$JQ_BIN" -c 'map([.id, .status])' "$SCANNED")" == '[["CVE-2024-0001","analyzed"]]' ]]
