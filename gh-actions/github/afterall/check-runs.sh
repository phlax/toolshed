#!/usr/bin/env bash

set -e -o pipefail

PAGE=2
OUTPUT=$(gh api --jq "${SCRIPT_JQ}" "/repos/${REPO}/actions/runs?page=${PAGE}&head_sha=${HEAD_SHA}&status=completed&per_page=${PER_PAGE}")

for PAGE in $(seq 1 "${MAX_PAGES}"); do
    echo "CHECK PAGE: ${PAGE}" >&2
    PAGE_OUTPUT=$(gh api --jq "${SCRIPT_JQ}" "/repos/${REPO}/actions/runs?page=${PAGE}&head_sha=${HEAD_SHA}&status=completed&per_page=${PER_PAGE}")
    # OUTPUT=$(jq -c --argjson a "$OUTPUT" --argjson b "$PAGE_OUTPUT" '$a+$b')
done


echo "$OUTPUT"
