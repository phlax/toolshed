#!/usr/bin/env bash
set -euo pipefail

f=bazel_tools/tools/bash/runfiles/runfiles.bash
# shellcheck disable=SC1090
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null ||
    source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null ||
    source "$0.runfiles/$f" 2>/dev/null ||
    { echo >&2 "ERROR: cannot find runfiles.bash"; exit 1; }

JQ_BIN="$(rlocation "$JQ_BIN")"
CPE_DEPS="$(rlocation "$CPE_DEPS")"
CVES_IGNORED="$(rlocation "$CVES_IGNORED")"
JQ_CVE_MATCHER="$(rlocation "$JQ_CVE_MATCHER")"
JQ_CNA_MATCHER="$(rlocation "$JQ_CNA_MATCHER")"
JQ_CVE_ANALYZED="$(rlocation "$JQ_CVE_ANALYZED")"
CVE_FILES="$(rlocation "$CVE_FILES")"

# NVD month files are at the root of the data directory, CVE Program
# (cvelistV5) month files under `cvelist/`.
nvd_files=()
cna_files=()
while IFS= read -r file; do
    if [[ "$file" == */cvelist/* ]]; then
        cna_files+=("$(rlocation "$file")")
    else
        nvd_files+=("$(rlocation "$file")")
    fi
done < "$CVE_FILES"
if [[ ${#nvd_files[@]} -eq 0 ]]; then
    echo >&2 "No CVE data set"
    exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

"$JQ_BIN" -f "$JQ_CVE_MATCHER" \
    --slurpfile deps "$CPE_DEPS" --slurpfile ignored "$CVES_IGNORED" "${nvd_files[@]}" |
    "$JQ_BIN" -s '[.[][] | .status = "analyzed"]' > "$tmpdir/nvd.json"

if [[ ${#cna_files[@]} -eq 0 ]]; then
    cat "$tmpdir/nvd.json"
    exit 0
fi

# Where NVD has analyzed a CVE (ie it has CPE configurations) it is
# authoritative: CNA matches are only kept for CVEs it has not.
"$JQ_BIN" -f "$JQ_CVE_ANALYZED" "${nvd_files[@]}" |
    "$JQ_BIN" -s '[.[][]]' > "$tmpdir/analyzed.json"
# shellcheck disable=SC2016
"$JQ_BIN" -f "$JQ_CNA_MATCHER" \
    --slurpfile deps "$CPE_DEPS" --slurpfile ignored "$CVES_IGNORED" "${cna_files[@]}" |
    "$JQ_BIN" -s --slurpfile analyzed "$tmpdir/analyzed.json" \
        '[.[][] | select(.id as $id | $analyzed[0] | index($id) | not) | .status = "pending"]' \
        > "$tmpdir/cna.json"
"$JQ_BIN" -s 'add' "$tmpdir/nvd.json" "$tmpdir/cna.json"
