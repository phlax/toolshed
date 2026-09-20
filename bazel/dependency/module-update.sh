#!/bin/bash
set -euo pipefail

usage(){ cat <<'EOF'
Usage:
  module-update.sh <MODULE.bazel> <deps.json> [--bazelrc=<path>] [--registry=<url>]... --report [--json-out=<path>] [--fail-on-outdated]
  module-update.sh <MODULE.bazel> <deps.json> <dep>[=<version>] [--registry=<url>] [--allow-yanked]
EOF
}
normalize_registry(){ printf '%s/\n' "${1%/}"; }
fetch_metadata(){
  local registry="$1" dep="$2" out="$3" rel="modules/${dep}/metadata.json" status
  if [[ "$registry" == file://* ]]; then cp "${registry#file://}/$rel" "$out" 2>/dev/null || return 1; return 0; fi
  if [[ "$registry" != *://* ]]; then cp "${registry%/}/$rel" "$out" 2>/dev/null || return 1; return 0; fi
  status="$(${CURL_BIN:-curl} -sSL -o "$out" -w '%{http_code}' "${registry}${rel}")" || { echo "Failed to fetch ${registry}${rel}" >&2; exit 1; }
  [[ "$status" == 404 ]] && { rm -f "$out"; return 1; }
  [[ "$status" =~ ^2 ]] || { echo "Unexpected status ${status} fetching ${registry}${rel}" >&2; exit 1; }
}
resolve_module(){ [[ -z "${BUILD_WORKSPACE_DIRECTORY:-}" ]] && printf '%s\n' "$MODULE_FILE" || (cd "$BUILD_WORKSPACE_DIRECTORY" && realpath "$MODULE_FILE"); }
run_buildozer(){ local cmd="$1" label="$2" err="$TMPDIR/buildozer.err"; set +e; "$BUILDOZER" "$cmd" "$label" >/dev/null 2>"$err"; rc=$?; set -e; return $rc; }

MODULE_FILE="$1"; DEP_DATA="$2"; shift 2
JQ="${JQ_BIN:-jq}"; BUILDOZER="${BUILDOZER:-}"; JQ_DIR="${MODULE_UPDATER_JQ_DIR:-}"
[[ -f "$JQ_DIR" ]] && JQ_DIR="${JQ_DIR%/*}"
REPORT=0; FAIL_ON_OUTDATED=0; ALLOW_YANKED=false; JSON_OUT=""; BAZELRC="${MODULE_UPDATER_BAZELRC:-/dev/null}"; DEP=""; REQUESTED_VERSION=""; REQUESTED_REGISTRY=""
TMPDIR="$(mktemp -d)"; trap 'rm -rf "$TMPDIR"' EXIT
: >"$TMPDIR/extra_registries"
while (($#)); do
  case "$1" in
    --report) REPORT=1 ;;
    --fail-on-outdated) FAIL_ON_OUTDATED=1 ;;
    --allow-yanked) ALLOW_YANKED=true ;;
    --json-out=*) JSON_OUT="${1#*=}" ;;
    --json-out) JSON_OUT="$2"; shift ;;
    --bazelrc=*) BAZELRC="${1#*=}" ;;
    --bazelrc) BAZELRC="$2"; shift ;;
    --registry=*) REQUESTED_REGISTRY="$(normalize_registry "${1#*=}")"; printf '%s\n' "$REQUESTED_REGISTRY" >>"$TMPDIR/extra_registries" ;;
    --registry) REQUESTED_REGISTRY="$(normalize_registry "$2")"; printf '%s\n' "$REQUESTED_REGISTRY" >>"$TMPDIR/extra_registries"; shift ;;
    --help|-h) usage; exit 0 ;;
    --*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) [[ -n "$DEP" ]] && { usage >&2; exit 1; }; DEP="$1" ;;
  esac; shift
done
[[ -n "$DEP" ]] || REPORT=1
[[ "$DEP" == *=* ]] && REQUESTED_VERSION="${DEP#*=}" DEP="${DEP%%=*}"
EXTRA_JSON="$($JQ -Rsc 'split("\n") | map(select(length > 0))' <"$TMPDIR/extra_registries")"
REGISTRIES_JSON="$($JQ -Rsc --argjson extra "$EXTRA_JSON" -f "$JQ_DIR/registries.jq" <"$BAZELRC")"
[[ "$REGISTRIES_JSON" != '[]' ]] || { echo "No registries configured. Pass --bazelrc or --registry." >&2; exit 1; }
DEPS_JSON="$($JQ -rc 'to_entries | map(select(.value.version | type == "string") | .key)' "$DEP_DATA")"
idx=0
while IFS= read -r registry; do
  mkdir -p "$TMPDIR/$idx"
  while IFS= read -r dep; do fetch_metadata "$registry" "$dep" "$TMPDIR/$idx/$dep.json" || true; done < <($JQ -r '.[]' <<<"$DEPS_JSON")
  idx=$((idx + 1))
done < <($JQ -r '.[]' <<<"$REGISTRIES_JSON")
find "$TMPDIR" -path '*/[0-9]*/*.json' | sort >"$TMPDIR/files"
META_FILTER='def base: reduce $regs[] as $r ({}; .[$r] = (reduce $deps[] as $d ({}; .[$d] = null))); reduce inputs as $m (base; (input_filename | capture("/(?<i>[0-9]+)/(?<dep>[^/]+)\\.json$")) as $p | .[$regs[$p.i|tonumber]][$p.dep] = $m)'
if [[ -s "$TMPDIR/files" ]]; then METADATA_JSON="$($JQ -n --argjson regs "$REGISTRIES_JSON" --argjson deps "$DEPS_JSON" "$META_FILTER" $(cat "$TMPDIR/files"))"; else METADATA_JSON="$($JQ -n --argjson regs "$REGISTRIES_JSON" --argjson deps "$DEPS_JSON" 'reduce $regs[] as $r ({}; .[$r] = (reduce $deps[] as $d ({}; .[$d] = null)))')"; fi
$JQ -n --argjson deps "$(cat "$DEP_DATA")" --argjson registries "$REGISTRIES_JSON" --argjson metadata "$METADATA_JSON" '{deps: $deps, registries: $registries, metadata: $metadata}' >"$TMPDIR/report_input.json"
REPORT_JSON="$($JQ -S -L "$JQ_DIR" -f "$JQ_DIR/report.jq" "$TMPDIR/report_input.json")"
if (( REPORT == 1 )); then
  [[ -n "$JSON_OUT" ]] && printf '%s\n' "$REPORT_JSON" >"$JSON_OUT" || printf '%s\n' "$REPORT_JSON"
  if (( FAIL_ON_OUTDATED == 1 )) && $JQ -e 'any(.[]; .update_available)' <<<"$REPORT_JSON" >/dev/null; then exit 1; fi
  exit 0
fi
[[ -x "$BUILDOZER" ]] || { echo "buildozer binary not found: ${BUILDOZER}" >&2; exit 1; }
RESOLUTION="$($JQ -cn -L "$JQ_DIR" --arg dep "$DEP" --arg requested_version "$REQUESTED_VERSION" --arg requested_registry "$REQUESTED_REGISTRY" --argjson allow_yanked "$ALLOW_YANKED" --argjson report_entry "$($JQ -c --arg dep "$DEP" '.[$dep] // null' <<<"$REPORT_JSON")" '{dep: $dep, report_entry: $report_entry, requested_version: $requested_version, requested_registry: $requested_registry, allow_yanked: $allow_yanked}' | $JQ -L "$JQ_DIR" -f "$JQ_DIR/resolve.jq")"
ERR="$($JQ -r '.error // empty' <<<"$RESOLUTION")"; [[ -z "$ERR" ]] || { echo "$ERR" >&2; exit 1; }
MODULE_PATH="$(resolve_module)"; grep -Eq '^[[:space:]]*module[[:space:]]*\(' "$MODULE_PATH" || { echo "Expected module() declaration in ${MODULE_PATH}" >&2; exit 1; }
TARGET="$($JQ -r '.target' <<<"$RESOLUTION")"; CURRENT="$($JQ -r --arg dep "$DEP" '.[$dep].current' <<<"$REPORT_JSON")"; CHANGED=0; rc=0
if [[ "$TARGET" == "$CURRENT" ]]; then echo "${DEP}: already at ${TARGET}"; exit 0; fi
run_buildozer "set version \"$TARGET\"" "${MODULE_PATH}:${DEP}" || rc=$?
if (( rc == 3 )); then :; elif (( rc == 0 )); then CHANGED=1; else grep -Eq 'rule .+ not found|no rule' "$TMPDIR/buildozer.err" && { echo "Dependency ${DEP} not found in ${MODULE_PATH}" >&2; exit 1; }; cat "$TMPDIR/buildozer.err" >&2; exit $rc; fi
while IFS=: read -r line _; do
  [[ -n "$line" ]] || continue
  sed -n "${line},$((line + 12))p" "$MODULE_PATH" | grep -Eq "module_name[[:space:]]*=[[:space:]]*\"${DEP}\"" || continue
  rc=0
  run_buildozer "set version \"$TARGET\"" "${MODULE_PATH}:%${line}" || rc=$?
  (( rc == 0 )) && CHANGED=1
  (( rc == 0 || rc == 3 )) || { cat "$TMPDIR/buildozer.err" >&2; exit $rc; }
done < <(grep -nE '^[[:space:]]*single_version_override[[:space:]]*\(' "$MODULE_PATH" || true)
if (( CHANGED == 0 )); then echo "${DEP}: already at ${TARGET}"; else echo "${DEP}: ${CURRENT} -> ${TARGET}"; fi
