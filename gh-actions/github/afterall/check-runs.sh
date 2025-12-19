#!/usr/bin/env bash

set -e -o pipefail

OUTPUT='{"workflow_runs": []}'

echo "$WF_NAMES"

for PAGE in $(seq 1 "${MAX_PAGES}"); do
    PAGE_OUTPUT=$(gh api --jq "${SCRIPT_JQ}" "/repos/${REPO}/actions/runs?page=${PAGE}&head_sha=${HEAD_SHA}&per_page=${PER_PAGE}")
    echo "CHECK PAGE: ${PAGE}: ${PAGE_OUTPUT}" >&2
    OUTPUT=$(echo "$OUTPUT" | jq -c --argjson page "$PAGE_OUTPUT" '{workflow_runs: (.workflow_runs + $page.workflow_runs)}')
    echo "CHECK PAGE OUTPUT: ${PAGE}: ${OUTPUT}" >&2
done


echo "$OUTPUT"
