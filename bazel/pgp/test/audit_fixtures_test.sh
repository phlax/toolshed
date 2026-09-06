#!/usr/bin/env bash
#
# Exercises `audit_test.sh` against captured `bazel aquery` output.
#
# `fixtures/audit.json` is the real aquery output for the example signing
# targets in this package and must pass. The broken variants below each
# break one of the guarantees the audit checks for - a removed execution
# requirement, a leaked environment variable, key material as an action
# input, a passphrase on the command line - and must be rejected. They are
# derived from `fixtures/audit.json` with `jq` at test time rather than
# committed as separate ~1000-line JSON fixtures.

set -euo pipefail

JQ="${JQ_BIN:-jq}"
AUDIT="$(dirname "$0")/audit_test.sh"
FIXTURE="$(dirname "$0")/fixtures/audit.json"
PASSPHRASE="correct-horse-battery-staple"

if [[ ! -x "$AUDIT" ]]; then
    AUDIT="bash ${AUDIT}"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Remove one required execution requirement from every `OpenPGPSign` action.
MISSING_EXECUTION_REQUIREMENT="${TMP}/audit-missing-execution-requirement.json"
"$JQ" '
    .actions |= map(
        if .mnemonic == "OpenPGPSign" then
            .executionInfo |= map(select(.key != "no-cache"))
        else . end)
    ' "$FIXTURE" > "$MISSING_EXECUTION_REQUIREMENT"

# Leak `HOME` into the environment of every `OpenPGPSign` action.
ENVIRONMENT_LEAK="${TMP}/audit-environment-leak.json"
"$JQ" '
    .actions |= map(
        if .mnemonic == "OpenPGPSign" then
            .environmentVariables = ((.environmentVariables // []) + [{"key": "HOME", "value": "/x"}])
        else . end)
    ' "$FIXTURE" > "$ENVIRONMENT_LEAK"

# Append a `--passphrase=...` argument to every `OpenPGPSign` action's argv.
PASSPHRASE_ARGV="${TMP}/audit-passphrase-argv.json"
"$JQ" --arg passphrase "$PASSPHRASE" '
    .actions |= map(
        if .mnemonic == "OpenPGPSign" then
            .arguments += ["--passphrase=" + $passphrase]
        else . end)
    ' "$FIXTURE" > "$PASSPHRASE_ARGV"

# Add an input that looks like private key material (a `.gnupg` keyring
# file), reachable from an `OpenPGPSign` action's `inputDepSetIds` via a new
# `depSetOfFiles` entry - matching the shape real `aquery` output has, rather
# than hand-inserting a field (eg `execPath`) that real output never has.
KEY_MATERIAL_INPUT="${TMP}/audit-key-material-input.json"
"$JQ" '
    ([.pathFragments[].id] | max) as $f0
    | ([.artifacts[].id] | max) as $a0
    | ([.depSetOfFiles[].id] | max) as $d0
    | ($f0 + 1) as $f1
    | ($f0 + 2) as $f2
    | ($f0 + 3) as $f3
    | ($a0 + 1) as $art
    | ($d0 + 1) as $ds
    | .pathFragments += [
        {"id": $f1, "label": ".gnupg"},
        {"id": $f2, "label": "private-keys-v1.d", "parentId": $f1},
        {"id": $f3, "label": "DEADBEEF.key", "parentId": $f2}
      ]
    | .artifacts += [{"id": $art, "pathFragmentId": $f3}]
    | .depSetOfFiles += [{"id": $ds, "directArtifactIds": [$art]}]
    | (.actions | map(.mnemonic == "OpenPGPSign") | index(true)) as $idx
    | .actions[$idx].inputDepSetIds += [$ds]
    ' "$FIXTURE" > "$KEY_MATERIAL_INPUT"

failed=0

audit () {
    $AUDIT --forbid "$PASSPHRASE" --aquery-json "$1"
}

echo "# audit passes for compliant actions"
if ! audit "$FIXTURE"; then
    echo "FAIL: audit rejected compliant actions" >&2
    failed=1
fi

for fixture in \
    "$MISSING_EXECUTION_REQUIREMENT" \
    "$ENVIRONMENT_LEAK" \
    "$PASSPHRASE_ARGV" \
    "$KEY_MATERIAL_INPUT"; do
    echo "# audit fails for $(basename "$fixture")"
    if audit "$fixture"; then
        echo "FAIL: audit accepted $(basename "$fixture")" >&2
        failed=1
    fi
done

if [[ "$failed" -ne 0 ]]; then
    exit 1
fi

echo "audit fixtures test passed"
