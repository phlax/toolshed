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
JQ_NVD_SCAN="$(rlocation "$JQ_NVD_SCAN")"
CVES_PENDING="$(rlocation "$CVES_PENDING")"
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

# `pending: skip` scans NVD data only.
pending="$("$JQ_BIN" -r '.' "$CVES_PENDING")"
if [[ "$pending" == "skip" || ${#cna_files[@]} -eq 0 ]]; then
    "$JQ_BIN" -f "$JQ_CVE_MATCHER" \
        --slurpfile deps "$CPE_DEPS" --slurpfile ignored "$CVES_IGNORED" "${nvd_files[@]}" |
        "$JQ_BIN" -s '[.[][] | .status = "analyzed"]'
    exit 0
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# One pass over the NVD data: the matches, and the ids NVD has analyzed
# (ie that have CPE configurations). Where NVD has analyzed a CVE it is
# authoritative, so CNA matches are only kept for CVEs it has not.
"$JQ_BIN" -f "$JQ_NVD_SCAN" \
    --slurpfile deps "$CPE_DEPS" --slurpfile ignored "$CVES_IGNORED" "${nvd_files[@]}" |
    "$JQ_BIN" -s '{matches: [.[].matches[] | .status = "analyzed"], analyzed: [.[].analyzed[]]}' \
        > "$tmpdir/nvd.json"
# shellcheck disable=SC2016
"$JQ_BIN" -f "$JQ_CNA_MATCHER" \
    --slurpfile deps "$CPE_DEPS" --slurpfile ignored "$CVES_IGNORED" "${cna_files[@]}" |
    "$JQ_BIN" -s --slurpfile nvd "$tmpdir/nvd.json" \
        '$nvd[0].matches
         + [.[][] | select(.id as $id | $nvd[0].analyzed | index($id) | not) | .status = "pending"]'
