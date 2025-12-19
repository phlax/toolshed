#!/bin/bash -e

set -o pipefail

gh api --jq "${SCRIPT_JQ}" "/repos/${REPO}/actions/runs?page=${PAGE}&head_sha=${HEAD_SHA}&status=completed&per_page=${PER_PAGE}"
