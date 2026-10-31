#!/usr/bin/env bash
# A jq_binary without main or filter takes the program and flags from its
# arguments, with its libraries importable.
set -euo pipefail
source "$TEST_SRCDIR/bazel_tools/tools/bash/runfiles/runfiles.bash"
actual="$("$(rlocation "$1")" -n -r --arg who ' world ' 'import "greet" as greet; $who | greet::hello')"
[[ "$actual" == "Hello world" ]] || {
    echo "expected 'Hello world', got '$actual'" >&2
    exit 1
}
