#!/bin/bash
set -euo pipefail

: "${SQ:?SQ must be set}"
: "${SQ_VERSION:?SQ_VERSION must be set}"
: "${REPO_NAME_FILE:?REPO_NAME_FILE must be set}"

repo_name=$(tr -d '\n' <"$REPO_NAME_FILE")
version="$("$SQ" version 2>&1 || true)"
test "${version%%$'\n'*}" = "sq $SQ_VERSION"

if [[ "${EXPECT_SOURCE_ONLY:-0}" == "1" ]]; then
    echo "$repo_name" | grep -Eq '^[A-Za-z0-9_+.-]*$'
    if [[ "$repo_name" == *sq_toolchains* ]]; then
        echo "expected source toolchain, got prebuilt repo $repo_name" >&2
        exit 1
    fi
else
    echo "$repo_name" | grep -Eq '^[A-Za-z0-9_+.-]+$'
    [[ "$repo_name" == *sq_toolchains* ]]
fi

echo "PASS: sq toolchain version checks passed"
