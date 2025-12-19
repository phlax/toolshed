#!/usr/bin/env bash

set -e -o pipefail

OUTPUT='{workflow_runs: []}'

for PAGE in $(seq 1 "${MAX_PAGES}"); do
    PAGE_OUTPUT=$(gh api --jq "${SCRIPT_JQ}" "/repos/${REPO}/actions/runs?page=${PAGE}&head_sha=${HEAD_SHA}&status=completed&per_page=${PER_PAGE}")
    echo "CHECK PAGE: ${PAGE}: ${PAGE_OUTPUT}" >&2
    OUTPUT=$(jq -c --argjson a "$OUTPUT" --argjson b "$PAGE_OUTPUT" '{workflow_runs: $a.workflow_runs | $b.workflow_runs')
    echo "CHECK PAGE OUTPUT: ${PAGE}: ${OUTPUT}" >&2
done


echo "$OUTPUT"
