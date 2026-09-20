#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/version-compare.sh"

MODULE_FILE="${1:-}"
DEP_DATA="${2:-}"
shift 2 || true

JQ="${JQ_BIN:-jq}"
if [[ -z "$JQ" || ! -x "$JQ" ]]; then
    echo "jq binary not found: ${JQ}" >&2
    exit 1
fi

REPORT_MODE=0
FAIL_ON_OUTDATED=0
ALLOW_YANKED=0
JSON_OUT=""
SELECTED_DEP=""
TARGET_VERSION=""
BAZELRC="${MODULE_UPDATER_BAZELRC:-}"
REQUESTED_REGISTRY=""
declare -a REGISTRIES=()

normalize_registry() {
    local registry="${1%/}"
    printf '%s/\n' "$registry"
}

load_env_registries() {
    if [[ -z "${MODULE_UPDATER_REGISTRIES:-}" ]]; then
        return 0
    fi
    while IFS= read -r registry; do
        [[ -n "$registry" ]] && REGISTRIES+=("$(normalize_registry "$registry")")
    done <<< "${MODULE_UPDATER_REGISTRIES}"
}

parse_args() {
    local positional=()
    while (($#)); do
        case "$1" in
            --report)
                REPORT_MODE=1
                ;;
            --fail-on-outdated)
                FAIL_ON_OUTDATED=1
                ;;
            --allow-yanked)
                ALLOW_YANKED=1
                ;;
            --json-out=*)
                JSON_OUT="${1#*=}"
                ;;
            --json-out)
                JSON_OUT="${2:-}"
                shift
                ;;
            --bazelrc=*)
                BAZELRC="${1#*=}"
                ;;
            --bazelrc)
                BAZELRC="${2:-}"
                shift
                ;;
            --registry=*)
                REQUESTED_REGISTRY="$(normalize_registry "${1#*=}")"
                ;;
            --registry)
                REQUESTED_REGISTRY="$(normalize_registry "${2:-}")"
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            --*)
                echo "Unknown option: $1" >&2
                exit 1
                ;;
            *)
                positional+=("$1")
                ;;
        esac
        shift
    done

    if (( ${#positional[@]} > 0 )); then
        SELECTED_DEP="${positional[0]}"
        if [[ "$SELECTED_DEP" == *=* ]]; then
            TARGET_VERSION="${SELECTED_DEP#*=}"
            SELECTED_DEP="${SELECTED_DEP%%=*}"
        fi
    fi

    if [[ -z "$SELECTED_DEP" ]]; then
        REPORT_MODE=1
    fi
}

usage() {
    cat <<'EOF'
Usage:
  module-update.sh <MODULE.bazel> <dependencies.json> --report [--json-out=<path>] [--fail-on-outdated]
  module-update.sh <MODULE.bazel> <dependencies.json> <dep>[=<version>] [--registry=<url>] [--allow-yanked]
EOF
}

parse_bazelrc_registries() {
    local bazelrc_path="$1"
    local line
    local trimmed
    local registry

    while IFS= read -r line || [[ -n "$line" ]]; do
        trimmed="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$trimmed" || "$trimmed" == \#* ]] && continue
        trimmed="${trimmed%%#*}"
        if [[ "$trimmed" =~ ^(common|build)(:[^[:space:]]+)?[[:space:]]+--registry=([^[:space:]]+)[[:space:]]*$ ]]; then
            registry="$(normalize_registry "${BASH_REMATCH[3]}")"
            REGISTRIES+=("$registry")
        fi
    done < "$bazelrc_path"
}

dedupe_registries() {
    local deduped=()
    local registry
    local existing
    local duplicate

    for registry in "${REGISTRIES[@]}"; do
        duplicate=0
        for existing in "${deduped[@]}"; do
            if [[ "$existing" == "$registry" ]]; then
                duplicate=1
                break
            fi
        done
        if (( duplicate == 0 )); then
            deduped+=("$registry")
        fi
    done
    REGISTRIES=("${deduped[@]}")
}

prepare_registries() {
    load_env_registries
    if [[ -n "$BAZELRC" ]]; then
        parse_bazelrc_registries "$BAZELRC"
    fi
    if [[ -n "$REQUESTED_REGISTRY" ]]; then
        REGISTRIES+=("$REQUESTED_REGISTRY")
    fi
    dedupe_registries
    if (( ${#REGISTRIES[@]} == 0 )); then
        echo "No registries configured. Pass --bazelrc or --registry." >&2
        exit 1
    fi
}

json_array_from_values() {
    if (($# == 0)); then
        printf '[]'
        return 0
    fi
    printf '%s\n' "$@" | "$JQ" -Rcs 'split("\n")[:-1]'
}

ensure_curl_bin() {
    if [[ -n "${CURL_BIN:-}" ]]; then
        if [[ ! -x "$CURL_BIN" ]]; then
            echo "curl binary not found: ${CURL_BIN}" >&2
            exit 1
        fi
        printf '%s' "$CURL_BIN"
        return 0
    fi
    if command -v curl >/dev/null 2>&1; then
        command -v curl
        return 0
    fi
    echo "curl is required for http(s) registries; set CURL_BIN to an explicit executable" >&2
    exit 1
}

fetch_metadata() {
    local registry="$1"
    local dep="$2"
    local metadata_rel="modules/${dep}/metadata.json"
    local file_path=""
    local curl_bin
    local status
    local output

    if [[ "$registry" == file://* ]]; then
        file_path="${registry#file://}/${metadata_rel}"
        [[ -f "$file_path" ]] || return 1
        cat "$file_path"
        return 0
    fi

    if [[ "$registry" != *://* ]]; then
        file_path="${registry%/}/${metadata_rel}"
        [[ -f "$file_path" ]] || return 1
        cat "$file_path"
        return 0
    fi

    curl_bin="$(ensure_curl_bin)"
    output="$(mktemp)"
    status="$("$curl_bin" -sSL -o "$output" -w '%{http_code}' "${registry}${metadata_rel}")" || {
        rm -f "$output"
        echo "Failed to fetch ${registry}${metadata_rel}" >&2
        exit 1
    }
    if [[ "$status" == 404 ]]; then
        rm -f "$output"
        return 1
    fi
    if [[ ! "$status" =~ ^2 ]]; then
        rm -f "$output"
        echo "Unexpected status ${status} fetching ${registry}${metadata_rel}" >&2
        exit 1
    fi
    cat "$output"
    rm -f "$output"
}

dep_entries() {
    "$JQ" -c '
        to_entries[]
        | select(.value | type == "object" and (.version? | type == "string"))
        | {
            name: .key,
            version: .value.version,
            registry: (.value.registry // ""),
          }
    ' "$DEP_DATA"
}

build_dep_report_json() {
    local dep="$1"
    local current="$2"
    local hinted_registry="${3:-}"
    local current_registry=""
    local latest=""
    local registry
    local metadata
    local versions_json
    local yanked_json
    local latest_registry_version
    local registry_fragments=()
    local latest_fragments=()
    local versions=()
    local yanked=()
    local non_yanked_versions=()
    local version
    local yanked_version
    local is_yanked
    local registry_fragment
    local latest_fragment

    if [[ -n "$hinted_registry" ]]; then
        current_registry="$(normalize_registry "$hinted_registry")"
    fi

    for registry in "${REGISTRIES[@]}"; do
        metadata="$(fetch_metadata "$registry" "$dep" || true)"
        [[ -n "$metadata" ]] || continue
        versions=()
        yanked=()
        while IFS= read -r version; do
            [[ -n "$version" ]] && versions+=("$version")
        done < <(printf '%s' "$metadata" | "$JQ" -r '.versions[]?')
        while IFS= read -r yanked_version; do
            [[ -n "$yanked_version" ]] && yanked+=("$yanked_version")
        done < <(printf '%s' "$metadata" | "$JQ" -r '(.yanked_versions // {}) | keys[]?')

        versions_json="$(json_array_from_values $(sort_versions "${versions[@]}"))"
        if (( ${#yanked[@]} > 0 )); then
            yanked_json="$(json_array_from_values $(sort_versions "${yanked[@]}"))"
        else
            yanked_json='[]'
        fi
        registry_fragment="$("$JQ" -cn \
            --arg registry "$registry" \
            --argjson versions "$versions_json" \
            --argjson yanked "$yanked_json" \
            '{($registry): {versions: $versions, yanked: $yanked}}')"
        registry_fragments+=("$registry_fragment")

        non_yanked_versions=()
        for version in "${versions[@]}"; do
            is_yanked=0
            for yanked_version in "${yanked[@]}"; do
                if [[ "$version" == "$yanked_version" ]]; then
                    is_yanked=1
                    break
                fi
            done
            if (( is_yanked == 0 )); then
                non_yanked_versions+=("$version")
            fi
        done
        latest_registry_version="$(latest_version "${non_yanked_versions[@]}")"
        if [[ -n "$latest_registry_version" ]]; then
            latest_fragment="$("$JQ" -cn --arg registry "$registry" --arg latest "$latest_registry_version" '{($registry): $latest}')"
            latest_fragments+=("$latest_fragment")
            if [[ -z "$latest" ]] || [[ "$(compare_versions "$latest_registry_version" "$latest")" == 1 ]]; then
                latest="$latest_registry_version"
            fi
        fi
        if [[ -z "$current_registry" ]]; then
            if printf '%s\n' "${versions[@]}" | grep -Fxq "$current"; then
                current_registry="$registry"
            fi
        fi
    done

    local registries_json='{}'
    local latest_by_registry_json='{}'
    local update_available=false

    if (( ${#registry_fragments[@]} > 0 )); then
        registries_json="$(printf '%s\n' "${registry_fragments[@]}" | "$JQ" -sc 'add // {}')"
    fi
    if (( ${#latest_fragments[@]} > 0 )); then
        latest_by_registry_json="$(printf '%s\n' "${latest_fragments[@]}" | "$JQ" -sc 'add // {}')"
    fi
    if [[ -n "$latest" && "$(compare_versions "$latest" "$current")" == 1 ]]; then
        update_available=true
    fi

    "$JQ" -S -cn \
        --arg current "$current" \
        --arg current_registry "$current_registry" \
        --arg latest "$latest" \
        --argjson latest_by_registry "$latest_by_registry_json" \
        --argjson registries "$registries_json" \
        --argjson update_available "$update_available" '
        {
          current: $current,
          current_registry: (if $current_registry == "" then null else $current_registry end),
          latest: (if $latest == "" then null else $latest end),
          latest_by_registry: $latest_by_registry,
          registries: $registries,
          update_available: $update_available,
        }'
}

write_report() {
    local output_file="$1"
    local any_outdated=false
    local report

    report="$(
        dep_entries | while IFS= read -r entry; do
            dep="$("$JQ" -r '.name' <<< "$entry")"
            current="$("$JQ" -r '.version' <<< "$entry")"
            registry="$("$JQ" -r '.registry' <<< "$entry")"
            "$JQ" -cn \
                --arg dep "$dep" \
                --argjson data "$(build_dep_report_json "$dep" "$current" "$registry")" \
                '{($dep): $data}'
        done | "$JQ" -S -sc 'add // {}'
    )"

    if [[ -n "$output_file" ]]; then
        printf '%s\n' "$report" > "$output_file"
    else
        printf '%s\n' "$report"
    fi

    if [[ "$("$JQ" -r 'any(.[]; .update_available)' <<< "$report")" == true ]]; then
        any_outdated=true
    fi
    if (( FAIL_ON_OUTDATED == 1 )) && [[ "$any_outdated" == true ]]; then
        return 1
    fi
}

resolve_workspace_module_file() {
    if [[ -z "${BUILD_WORKSPACE_DIRECTORY:-}" ]]; then
        printf '%s\n' "$MODULE_FILE"
        return 0
    fi
    pushd "${BUILD_WORKSPACE_DIRECTORY}" >/dev/null
    realpath "$MODULE_FILE"
    popd >/dev/null
}

update_module_file() {
    local module_path="$1"
    local dep="$2"
    local target="$3"
    local temp_file
    local status_file

    temp_file="$(mktemp)"
    status_file="$(mktemp)"

    awk -v dep="$dep" -v target="$target" -v status_file="$status_file" '
        function flush_block(    matched, new_block, old_version, rewritten) {
            matched = 0
            rewritten = block
            if (kind == "bazel_dep" && block ~ "name[[:space:]]*=[[:space:]]*\"" dep "\"") {
                matched = 1
            } else if (kind == "single_version_override" && block ~ "module_name[[:space:]]*=[[:space:]]*\"" dep "\"") {
                matched = 1
            }

            if (matched) {
                if (match(block, /version[[:space:]]*=[[:space:]]*"[^"]+"/)) {
                    old_version = substr(block, RSTART, RLENGTH)
                    sub(/^[^"]*"/, "", old_version)
                    sub(/".*$/, "", old_version)
                    rewritten = block
                    sub(/version[[:space:]]*=[[:space:]]*"[^"]+"/, "version = \"" target "\"", rewritten)
                    print kind "|" old_version "|" target "|" (rewritten != block ? "changed" : "unchanged") >> status_file
                }
            }
            printf "%s", rewritten
            block = ""
            kind = ""
            depth = 0
        }

        {
            if (depth == 0) {
                if ($0 ~ /bazel_dep[[:space:]]*\(/) {
                    kind = "bazel_dep"
                    block = $0 ORS
                    depth = gsub(/\(/, "(", $0) - gsub(/\)/, ")", $0)
                    if (depth <= 0) {
                        flush_block()
                    }
                    next
                }
                if ($0 ~ /single_version_override[[:space:]]*\(/) {
                    kind = "single_version_override"
                    block = $0 ORS
                    depth = gsub(/\(/, "(", $0) - gsub(/\)/, ")", $0)
                    if (depth <= 0) {
                        flush_block()
                    }
                    next
                }
                print
                next
            }

            block = block $0 ORS
            depth += gsub(/\(/, "(", $0)
            depth -= gsub(/\)/, ")", $0)
            if (depth <= 0) {
                flush_block()
            }
        }

        END {
            if (depth > 0) {
                flush_block()
            }
        }
    ' "$module_path" > "$temp_file"

    if [[ ! -s "$status_file" ]]; then
        rm -f "$temp_file" "$status_file"
        return 2
    fi
    if grep -q '|changed$' "$status_file"; then
        cp "$temp_file" "$module_path"
    fi
    cat "$status_file"
    rm -f "$temp_file" "$status_file"
}

version_in_registry() {
    local dep_report="$1"
    local registry="$2"
    local version="$3"
    "$JQ" -e --arg registry "$registry" --arg version "$version" '
        (.registries[$registry].versions // []) | index($version) != null
    ' <<< "$dep_report" >/dev/null
}

yanked_in_registry() {
    local dep_report="$1"
    local registry="$2"
    local version="$3"
    "$JQ" -e --arg registry "$registry" --arg version "$version" '
        (.registries[$registry].yanked // []) | index($version) != null
    ' <<< "$dep_report" >/dev/null
}

choose_registry_for_version() {
    local dep_report="$1"
    local current_registry="$2"
    local version="$3"
    local matches=()
    local registry

    while IFS= read -r registry; do
        [[ -n "$registry" ]] && matches+=("$registry")
    done < <("$JQ" -r --arg version "$version" '
        .registries
        | to_entries[]
        | select((.value.versions // []) | index($version) != null)
        | .key
    ' <<< "$dep_report")

    if [[ -n "$current_registry" ]]; then
        for registry in "${matches[@]}"; do
            if [[ "$registry" == "$current_registry" ]]; then
                printf '%s\n' "$registry"
                return 0
            fi
        done
    fi
    if (( ${#matches[@]} == 1 )); then
        printf '%s\n' "${matches[0]}"
        return 0
    fi
    if (( ${#matches[@]} == 0 )); then
        return 1
    fi
    echo "Version ${version} is available in multiple registries; pass --registry" >&2
    exit 1
}

update_dependency() {
    local dep="$1"
    local requested_version="$2"
    local current
    local hinted_registry
    local dep_report
    local current_registry
    local chosen_registry
    local target_version
    local workspace_module
    local update_status
    local update_rc=0
    local old_version

    current="$("$JQ" -r --arg dep "$dep" '.[$dep].version // empty' "$DEP_DATA")"
    hinted_registry="$("$JQ" -r --arg dep "$dep" '.[$dep].registry // empty' "$DEP_DATA")"
    if [[ -z "$current" ]]; then
        echo "Dependency ${dep} not found in dependency metadata" >&2
        exit 1
    fi

    dep_report="$(build_dep_report_json "$dep" "$current" "$hinted_registry")"
    current_registry="$("$JQ" -r '.current_registry // empty' <<< "$dep_report")"

    if [[ -n "$REQUESTED_REGISTRY" ]]; then
        chosen_registry="$REQUESTED_REGISTRY"
    elif [[ -n "$requested_version" ]]; then
        chosen_registry="$(choose_registry_for_version "$dep_report" "$current_registry" "$requested_version" || true)"
        if [[ -z "$chosen_registry" ]]; then
            echo "Version ${requested_version} for ${dep} is not published on any configured registry" >&2
            exit 1
        fi
    elif [[ -n "$current_registry" ]]; then
        chosen_registry="$current_registry"
    else
        chosen_registry="$("$JQ" -r '
            .registries
            | keys
            | if length == 1 then .[0] else empty end
        ' <<< "$dep_report")"
        if [[ -z "$chosen_registry" ]]; then
            echo "Unable to determine registry for ${dep}; pass --registry" >&2
            exit 1
        fi
    fi

    if [[ -n "$requested_version" ]]; then
        target_version="$requested_version"
    else
        target_version="$("$JQ" -r --arg registry "$chosen_registry" '.latest_by_registry[$registry] // empty' <<< "$dep_report")"
        if [[ -z "$target_version" ]]; then
            echo "No non-yanked version found for ${dep} on ${chosen_registry}" >&2
            exit 1
        fi
    fi

    if ! version_in_registry "$dep_report" "$chosen_registry" "$target_version"; then
        echo "Version ${target_version} for ${dep} is not published on ${chosen_registry}" >&2
        exit 1
    fi
    if (( ALLOW_YANKED == 0 )) && yanked_in_registry "$dep_report" "$chosen_registry" "$target_version"; then
        echo "Version ${target_version} for ${dep} is yanked on ${chosen_registry}; pass --allow-yanked to override" >&2
        exit 1
    fi

    workspace_module="$(resolve_workspace_module_file)"
    if [[ ! -f "$workspace_module" ]]; then
        echo "MODULE file not found: ${workspace_module}" >&2
        exit 1
    fi

    if ! update_status="$(update_module_file "$workspace_module" "$dep" "$target_version")"; then
        update_rc=$?
    fi
    if (( update_rc == 2 )); then
        echo "Dependency ${dep} not found in ${workspace_module}" >&2
        exit 1
    elif (( update_rc != 0 )); then
        exit "$update_rc"
    fi
    old_version="$(
        grep '^bazel_dep|' <<< "$update_status" | head -n1 | cut -d'|' -f2
    )"
    if [[ -z "$old_version" ]]; then
        old_version="$(head -n1 <<< "$update_status" | cut -d'|' -f2)"
    fi
    if ! grep -q '|changed$' <<< "$update_status"; then
        echo "${dep}: already at ${target_version}"
        return 0
    fi

    echo "${dep}: ${old_version} -> ${target_version}"
}

parse_args "$@"
prepare_registries

if (( REPORT_MODE == 1 )); then
    write_report "$JSON_OUT"
else
    update_dependency "$SELECTED_DEP" "$TARGET_VERSION"
fi
