#!/usr/bin/env bash
#
# Runs `//pgp/test:audit` against the real dependency graph of the example
# signing targets in this package, rather than captured `aquery` JSON.
#
# This is the live counterpart to `//pgp/test:audit_test` (which only
# exercises the audit script against fixtures): it actually re-invokes
# `bazel aquery` so a regression that only shows up in the real graph (eg a
# dropped execution requirement, or a leaked `HOME`) is caught in CI.
#
# Intended to be run with `bazel run //pgp/test:live_audit` from the
# workspace root - it shells out to a fresh `bazel aquery` invocation, so it
# cannot run as a sandboxed `bazel test`.

set -euo pipefail

cd "${BUILD_WORKSPACE_DIRECTORY:?must be run with \`bazel run\`}"

exec pgp/test/audit_test.sh \
    --@envoy_toolshed//pgp:key_path=/tmp/nonexistent-key#sha256=0000000000000000000000000000000000000000000000000000000000000000 \
    --@envoy_toolshed//pgp:passphrase_path=/tmp/nonexistent \
    "deps(//pgp/test:example_detached) + deps(//pgp/test:example_cleartext) + deps(//pgp/test:example_checksums) + deps(//pgp/test:example_deb_changes)"
