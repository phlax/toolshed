#!/bin/bash
# shellcheck disable=SC2016
set -euo pipefail

JQ="${JQ_BIN:-jq}"
f=bazel_tools/tools/bash/runfiles/runfiles.bash
# shellcheck disable=SC1090
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -d ' ' -f2-)" 2>/dev/null || {
    echo >&2 "ERROR: cannot find $f"
    exit 1
}
WORKSPACE_NAME="${TEST_WORKSPACE:-_main}"
REGISTRY_SCRIPT="$(rlocation "$WORKSPACE_NAME/dependency/registry.sh")"
ROOT_BAZELRC="$(rlocation "$WORKSPACE_NAME/dependency/test/testdata/registry/workspace/.bazelrc")"
API_BAZELRC="$(rlocation "$WORKSPACE_NAME/dependency/test/testdata/registry/workspace/api/.bazelrc")"
ROOT_MODULE="$(rlocation "$WORKSPACE_NAME/dependency/test/testdata/registry/workspace/MODULE.bazel")"
API_MODULE="$(rlocation "$WORKSPACE_NAME/dependency/test/testdata/registry/workspace/api/MODULE.bazel")"

if ! command -v git >/dev/null 2>&1; then
    echo "SKIP: git not installed"
    exit 0
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
WORKSPACE="$TMPDIR/workspace"
REGISTRY_SRC="$TMPDIR/registry-src"
REGISTRY_BARE="$TMPDIR/registry.git"
mkdir -p "$WORKSPACE" "$REGISTRY_SRC/modules/foo/1.0.0-20240101" "$REGISTRY_SRC/modules/foo/1.1.0-20250101"
cp "$ROOT_BAZELRC" "$WORKSPACE/.bazelrc"
mkdir -p "$WORKSPACE/api"
cp "$API_BAZELRC" "$WORKSPACE/api/.bazelrc"
cp "$ROOT_MODULE" "$WORKSPACE/MODULE.bazel"
cp "$API_MODULE" "$WORKSPACE/api/MODULE.bazel"

git -C "$TMPDIR" init -q -b main registry-src
cat > "$REGISTRY_SRC/modules/foo/metadata.json" <<'JSON'
{"versions":["1.0.0-20240101","1.1.0-20250101"]}
JSON
printf 'module(name = "foo")\n' > "$REGISTRY_SRC/modules/foo/1.0.0-20240101/MODULE.bazel"
printf 'module(name = "foo")\n' > "$REGISTRY_SRC/modules/foo/1.1.0-20250101/MODULE.bazel"
git -C "$REGISTRY_SRC" add modules
git -C "$REGISTRY_SRC" -c user.name=test -c user.email=test@example.com commit -qm v1
V1="$(git -C "$REGISTRY_SRC" rev-parse HEAD)"
rm -rf "$REGISTRY_SRC/modules/foo/1.0.0-20240101"
cat > "$REGISTRY_SRC/modules/foo/metadata.json" <<'JSON'
{"versions":["1.1.0-20250101"]}
JSON
git -C "$REGISTRY_SRC" add -A modules
git -C "$REGISTRY_SRC" -c user.name=test -c user.email=test@example.com commit -qm v2
V2="$(git -C "$REGISTRY_SRC" rev-parse HEAD)"
git clone -q --bare "$REGISTRY_SRC" "$REGISTRY_BARE"

BUILD_WORKSPACE_DIRECTORY="$WORKSPACE" \
JQ_BIN="$REGISTRY_JQ_BIN" \
JQ_MODULES_ROOT_MARKER="$REGISTRY_JQ_MODULES_ROOT_MARKER" \
REGISTRY_BAZELRC_FILES='[".bazelrc","api/.bazelrc"]' \
REGISTRY_BRANCH=main \
REGISTRY_MODULE_FILES='["MODULE.bazel","api/MODULE.bazel"]' \
REGISTRY_REPO="file://$REGISTRY_BARE" \
REGISTRY_URL_PREFIX="https://raw.githubusercontent.com/envoyproxy/bazel-registry/" \
"$REGISTRY_SCRIPT" --hash "$V2"

grep -q "$V2" "$WORKSPACE/.bazelrc"
grep -q "$V2" "$WORKSPACE/api/.bazelrc"
grep -q 'version = "1.1.0-20250101"' "$WORKSPACE/MODULE.bazel"
grep -q 'version = "1.1.0-20250101"' "$WORKSPACE/api/MODULE.bazel"
python - <<'PY' "$WORKSPACE/MODULE.bazel"
from pathlib import Path
path = Path(__import__('sys').argv[1])
text = path.read_text()
assert text.startswith('#\tkeep-tab\n')
assert text.endswith('\n')
PY
"$JQ" -e --arg hash "$V2" '.registry.new == $hash and .modules[0].to == "1.1.0-20250101"' "$WORKSPACE/registry-changes.json" >/dev/null

FAIL_WORKSPACE="$TMPDIR/fail-workspace"
mkdir -p "$FAIL_WORKSPACE/api"
cp "$ROOT_BAZELRC" "$FAIL_WORKSPACE/.bazelrc"
cp "$API_BAZELRC" "$FAIL_WORKSPACE/api/.bazelrc"
cp "$ROOT_MODULE" "$FAIL_WORKSPACE/MODULE.bazel"
cp "$API_MODULE" "$FAIL_WORKSPACE/api/MODULE.bazel"
BEFORE_MODULE="$(cat "$FAIL_WORKSPACE/MODULE.bazel")"
BEFORE_API_MODULE="$(cat "$FAIL_WORKSPACE/api/MODULE.bazel")"
BEFORE_BAZELRC="$(cat "$FAIL_WORKSPACE/.bazelrc")"
if BUILD_WORKSPACE_DIRECTORY="$FAIL_WORKSPACE" \
    JQ_BIN="$REGISTRY_JQ_BIN" \
    JQ_MODULES_ROOT_MARKER="$REGISTRY_JQ_MODULES_ROOT_MARKER" \
    REGISTRY_BAZELRC_FILES='[".bazelrc","api/.bazelrc"]' \
    REGISTRY_BRANCH=main \
    REGISTRY_MODULE_FILES='["MODULE.bazel","api/MODULE.bazel"]' \
    REGISTRY_REPO="file://$REGISTRY_BARE" \
    REGISTRY_URL_PREFIX="https://raw.githubusercontent.com/envoyproxy/bazel-registry/" \
    "$REGISTRY_SCRIPT" --hash "$V2" --set foo=9.9.9 >"$TMPDIR/fail.out" 2>&1; then
    echo "FAIL: expected invalid override to fail" >&2
    exit 1
fi
grep -q '^FAIL:' "$TMPDIR/fail.out"
[ "$BEFORE_BAZELRC" = "$(cat "$FAIL_WORKSPACE/.bazelrc")" ]
[ "$BEFORE_MODULE" = "$(cat "$FAIL_WORKSPACE/MODULE.bazel")" ]
[ "$BEFORE_API_MODULE" = "$(cat "$FAIL_WORKSPACE/api/MODULE.bazel")" ]
[ ! -e "$FAIL_WORKSPACE/registry-changes.json" ]
[ -n "$V1" ]
