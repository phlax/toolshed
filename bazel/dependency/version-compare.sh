#!/bin/bash

set -euo pipefail

token_type() {
    if [[ "$1" =~ ^[0-9]+$ ]]; then
        printf 'numeric'
    else
        printf 'string'
    fi
}

next_chunk() {
    local input="$1"
    if [[ -z "$input" ]]; then
        printf '\n'
        return 0
    fi
    if [[ "$input" =~ ^[0-9]+ ]]; then
        printf '%s\n' "${BASH_REMATCH[0]}"
    else
        printf '%s\n' "${input%%[0-9]*}"
    fi
}

compare_chunk() {
    local left="$1"
    local right="$2"
    local left_type
    local right_type

    left_type="$(token_type "$left")"
    right_type="$(token_type "$right")"
    if [[ "$left_type" == numeric && "$right_type" == numeric ]]; then
        if ((10#$left < 10#$right)); then
            printf -- '-1'
        elif ((10#$left > 10#$right)); then
            printf '1'
        else
            printf '0'
        fi
        return 0
    fi

    if [[ "$left_type" == numeric && "$right_type" != numeric ]]; then
        printf -- '-1'
    elif [[ "$left_type" != numeric && "$right_type" == numeric ]]; then
        printf '1'
    elif [[ "$left" < "$right" ]]; then
        printf -- '-1'
    elif [[ "$left" > "$right" ]]; then
        printf '1'
    else
        printf '0'
    fi
}

compare_identifier() {
    local left="$1"
    local right="$2"
    local left_rest="$left"
    local right_rest="$right"
    local left_chunk
    local right_chunk
    local result

    while [[ -n "$left_rest" || -n "$right_rest" ]]; do
        left_chunk="$(next_chunk "$left_rest")"
        right_chunk="$(next_chunk "$right_rest")"
        if [[ -z "$left_chunk" && -n "$right_chunk" ]]; then
            printf -- '-1'
            return 0
        elif [[ -n "$left_chunk" && -z "$right_chunk" ]]; then
            printf '1'
            return 0
        fi
        result="$(compare_chunk "$left_chunk" "$right_chunk")"
        if [[ "$result" != 0 ]]; then
            printf '%s' "$result"
            return 0
        fi
        left_rest="${left_rest:${#left_chunk}}"
        right_rest="${right_rest:${#right_chunk}}"
    done
    printf '0'
}

split_prerelease() {
    local version="$1"
    local prerelease="${version#*-}"
    if [[ "$prerelease" == "$version" ]]; then
        return 0
    fi
    printf '%s\n' "${prerelease//./$'\n'}"
}

split_release() {
    local version="${1%%-*}"
    printf '%s\n' "${version//./$'\n'}"
}

compare_component_lists() {
    local -n left_ref="$1"
    local -n right_ref="$2"
    local limit="${#left_ref[@]}"
    local result
    local index=0

    if (( ${#right_ref[@]} > limit )); then
        limit="${#right_ref[@]}"
    fi

    while (( index < limit )); do
        if (( index >= ${#left_ref[@]} )); then
            printf -- '-1'
            return 0
        elif (( index >= ${#right_ref[@]} )); then
            printf '1'
            return 0
        fi
        result="$(compare_identifier "${left_ref[index]}" "${right_ref[index]}")"
        if [[ "$result" != 0 ]]; then
            printf '%s' "$result"
            return 0
        fi
        ((index += 1))
    done

    printf '0'
}

compare_versions() {
    local left="$1"
    local right="$2"
    local left_release=()
    local right_release=()
    local left_prerelease=()
    local right_prerelease=()
    local left_has_prerelease=0
    local right_has_prerelease=0
    local result
    local part

    while IFS= read -r part; do
        [[ -n "$part" ]] && left_release+=("$part")
    done < <(split_release "$left")
    while IFS= read -r part; do
        [[ -n "$part" ]] && right_release+=("$part")
    done < <(split_release "$right")

    result="$(compare_component_lists left_release right_release)"
    if [[ "$result" != 0 ]]; then
        printf '%s' "$result"
        return 0
    fi

    if [[ "$left" == *-* ]]; then
        left_has_prerelease=1
        while IFS= read -r part; do
            [[ -n "$part" ]] && left_prerelease+=("$part")
        done < <(split_prerelease "$left")
    fi
    if [[ "$right" == *-* ]]; then
        right_has_prerelease=1
        while IFS= read -r part; do
            [[ -n "$part" ]] && right_prerelease+=("$part")
        done < <(split_prerelease "$right")
    fi

    if (( left_has_prerelease == 0 && right_has_prerelease == 1 )); then
        printf '1'
        return 0
    elif (( left_has_prerelease == 1 && right_has_prerelease == 0 )); then
        printf -- '-1'
        return 0
    elif (( left_has_prerelease == 0 && right_has_prerelease == 0 )); then
        printf '0'
        return 0
    fi

    compare_component_lists left_prerelease right_prerelease
}

sort_versions() {
    local versions=("$@")
    local swapped=1
    local index
    local result
    local temp

    while (( swapped == 1 )); do
        swapped=0
        for (( index = 0; index < ${#versions[@]} - 1; index += 1 )); do
            result="$(compare_versions "${versions[index]}" "${versions[index + 1]}")"
            if [[ "$result" == 1 ]]; then
                temp="${versions[index]}"
                versions[index]="${versions[index + 1]}"
                versions[index + 1]="$temp"
                swapped=1
            fi
        done
    done

    printf '%s\n' "${versions[@]}"
}

latest_version() {
    local versions=("$@")
    if (( ${#versions[@]} == 0 )); then
        return 0
    fi
    sort_versions "${versions[@]}" | tail -n1
}

usage() {
    cat <<'EOF'
Usage:
  version-compare.sh compare <left> <right>
  version-compare.sh sort <version> [<version> ...]
  version-compare.sh latest <version> [<version> ...]
EOF
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    case "${1:-}" in
        compare)
            shift
            compare_versions "${1:-}" "${2:-}"
            ;;
        sort)
            shift
            sort_versions "$@"
            ;;
        latest)
            shift
            latest_version "$@"
            ;;
        *)
            usage >&2
            exit 1
            ;;
    esac
fi
