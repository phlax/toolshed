#!/usr/bin/env bash

set -e -o pipefail

PAGE=2
OUTPUT=$(gh api --jq "${SCRIPT_JQ}" "/repos/${REPO}/actions/runs?page=${PAGE}&head_sha=${HEAD_SHA}&status=completed&per_page=${PER_PAGE}")

echo "$OUTPUT"
