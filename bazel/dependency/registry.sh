#!/bin/bash
# shellcheck disable=SC2016
set -euo pipefail

f=bazel_tools/tools/bash/runfiles/runfiles.bash
# shellcheck disable=SC1090
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -d ' ' -f2-)" 2>/dev/null || {
    echo >&2 "ERROR: cannot find $f"
    exit 1
}

JQ="$(rlocation "$JQ_BIN")"
JQ_LIB_DIR="$(dirname "$(rlocation "$JQ_MODULES_ROOT_MARKER")")"
WORKSPACE_DIR="${BUILD_WORKSPACE_DIRECTORY:-$PWD}"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

printf '%s\n' "$@" | "$JQ" -Rsc -L "$JQ_LIB_DIR" 'import "registry" as registry; split("\n")[:-1] | registry::parse_args' > "$TMPDIR/args.json"
printf '{}\n' > "$TMPDIR/bazelrc_files.json"
while IFS= read -r path; do
    "$JQ" -Rs --arg path "$path" '{($path): .}' < "$WORKSPACE_DIR/$path" > "$TMPDIR/one.json"
    "$JQ" -s 'add' "$TMPDIR/bazelrc_files.json" "$TMPDIR/one.json" > "$TMPDIR/next.json"
    mv "$TMPDIR/next.json" "$TMPDIR/bazelrc_files.json"
done < <("$JQ" -r '.[]' <<<"$REGISTRY_BAZELRC_FILES")
printf '{}\n' > "$TMPDIR/module_files.json"
while IFS= read -r path; do
    "$JQ" -Rs --arg path "$path" '{($path): .}' < "$WORKSPACE_DIR/$path" > "$TMPDIR/one.json"
    "$JQ" -s 'add' "$TMPDIR/module_files.json" "$TMPDIR/one.json" > "$TMPDIR/next.json"
    mv "$TMPDIR/next.json" "$TMPDIR/module_files.json"
done < <("$JQ" -r '.[]' <<<"$REGISTRY_MODULE_FILES")
CURRENT_HASH="$("$JQ" -rn -L "$JQ_LIB_DIR" --slurpfile files "$TMPDIR/bazelrc_files.json" --argjson paths "$REGISTRY_BAZELRC_FILES" --arg url_prefix "$REGISTRY_URL_PREFIX" 'import "registry" as registry; {files: $files[0], paths: $paths, url_prefix: $url_prefix} | registry::bazelrc_hash')"
TARGET_HASH="$("$JQ" -r '.hash // empty' "$TMPDIR/args.json")"
if [[ -z "$TARGET_HASH" ]]; then
    TARGET_HASH="$(git ls-remote "$REGISTRY_REPO" "refs/heads/$REGISTRY_BRANCH" | "$JQ" -Rsc -L "$JQ_LIB_DIR" 'import "registry" as registry; registry::ls_remote_hash')"
fi
git clone --quiet --bare --filter=blob:none "$REGISTRY_REPO" "$TMPDIR/registry.git"
"$JQ" -n -L "$JQ_LIB_DIR" --slurpfile files "$TMPDIR/module_files.json" --argjson paths "$REGISTRY_MODULE_FILES" 'import "registry" as registry; {files: $files[0], paths: $paths} | registry::module_pins' > "$TMPDIR/pins.json"
"$JQ" -r -L "$JQ_LIB_DIR" 'import "registry" as registry; registry::registry_objects[]' "$TMPDIR/pins.json" | while IFS= read -r path; do
    printf '%s:%s %s\n' "$TARGET_HASH" "$path" "$path"
done > "$TMPDIR/batch-check.in"
git -c safe.bareRepository=all -C "$TMPDIR/registry.git" cat-file --batch-check='%(rest) %(objecttype)' < "$TMPDIR/batch-check.in" | "$JQ" -Rsc -L "$JQ_LIB_DIR" --arg hash "$TARGET_HASH" 'import "registry" as registry; {hash: $hash, output: .} | registry::batch_check_exists' > "$TMPDIR/exists.json"
printf '{}\n' > "$TMPDIR/metadata.json"
"$JQ" -rn -L "$JQ_LIB_DIR" --slurpfile pins "$TMPDIR/pins.json" --slurpfile exists "$TMPDIR/exists.json" --slurpfile args "$TMPDIR/args.json" 'import "registry" as registry; {pins: $pins[0], exists: $exists[0], overrides: ($args[0].overrides // {})} | registry::metadata_modules[]?' | while IFS= read -r name; do
    git -c safe.bareRepository=all -C "$TMPDIR/registry.git" show "$TARGET_HASH:modules/$name/metadata.json" | "$JQ" -c --arg name "$name" '{($name): .}' > "$TMPDIR/one.json"
    "$JQ" -s 'add' "$TMPDIR/metadata.json" "$TMPDIR/one.json" > "$TMPDIR/next.json"
    mv "$TMPDIR/next.json" "$TMPDIR/metadata.json"
done
"$JQ" -n -L "$JQ_LIB_DIR" --slurpfile pins "$TMPDIR/pins.json" --slurpfile exists "$TMPDIR/exists.json" --slurpfile metadata "$TMPDIR/metadata.json" --slurpfile args "$TMPDIR/args.json" --arg current_hash "$CURRENT_HASH" --arg target_hash "$TARGET_HASH" 'import "registry" as registry; {pins: $pins[0], exists: $exists[0], metadata: $metadata[0], current_hash: $current_hash, target_hash: $target_hash, overrides: ($args[0].overrides // {})} | registry::plan' > "$TMPDIR/plan.json"
if [[ "$("$JQ" '.errors | length' "$TMPDIR/plan.json")" -gt 0 ]]; then
    "$JQ" -r '.errors[]' "$TMPDIR/plan.json" >&2
    exit 1
fi
"$JQ" -n -L "$JQ_LIB_DIR" --slurpfile files "$TMPDIR/bazelrc_files.json" --argjson paths "$REGISTRY_BAZELRC_FILES" --arg url_prefix "$REGISTRY_URL_PREFIX" --arg hash "$TARGET_HASH" 'import "registry" as registry; {files: $files[0], paths: $paths, url_prefix: $url_prefix, hash: $hash} | registry::apply_hash | to_entries | map({path: .key, content: .value})' > "$TMPDIR/hash_writes.json"
"$JQ" -n -L "$JQ_LIB_DIR" --slurpfile files "$TMPDIR/module_files.json" --slurpfile plan "$TMPDIR/plan.json" 'import "registry" as registry; {files: $files[0], edits: ($plan[0].edits // [])} | registry::apply_edits | to_entries | map({path: .key, content: .value})' > "$TMPDIR/module_writes.json"
"$JQ" -s 'add' "$TMPDIR/hash_writes.json" "$TMPDIR/module_writes.json" > "$TMPDIR/writes.json"
"$JQ" -c '.[]' "$TMPDIR/writes.json" | while IFS= read -r entry; do
    path="$("$JQ" -r '.path' <<<"$entry")"
    mkdir -p "$WORKSPACE_DIR/$(dirname "$path")"
    "$JQ" -rj '.content' <<<"$entry" > "$WORKSPACE_DIR/$path"
done
REPORT_PATH="$WORKSPACE_DIR/${REGISTRY_CHANGES_OUTPUT:-registry-changes.json}"
mkdir -p "$(dirname "$REPORT_PATH")"
"$JQ" '{registry, modules}' "$TMPDIR/plan.json" > "$REPORT_PATH"
"$JQ" -r -L "$JQ_LIB_DIR" 'import "registry" as registry; {registry, modules} | registry::render_report' "$TMPDIR/plan.json"
