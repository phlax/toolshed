#!/usr/bin/env bash
set -euo pipefail
source "$TEST_SRCDIR/bazel_tools/tools/bash/runfiles/runfiles.bash"
launcher="$(rlocation "$1")"
empty="$TEST_TMPDIR/empty_runfiles"
mkdir -p "$empty/bazel_tools/tools/bash/runfiles"
cp "$(rlocation bazel_tools/tools/bash/runfiles/runfiles.bash)" "$empty/bazel_tools/tools/bash/runfiles/"
status=0
env -u RUNFILES_MANIFEST_FILE RUNFILES_DIR="$empty" "$launcher" -n 2> "$TEST_TMPDIR/stderr" || status=$?
if [[ "$status" == 0 ]]; then
    echo "Expected a nonzero exit status for unresolved module roots" >&2
    exit 1
fi
grep -q "jq launcher: cannot resolve module root marker" "$TEST_TMPDIR/stderr" || {
    echo "Missing error message; stderr was:" >&2
    cat "$TEST_TMPDIR/stderr" >&2
    exit 1
}
