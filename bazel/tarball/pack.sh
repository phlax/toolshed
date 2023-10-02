#!/bin/bash -e

set -o pipefail

ZSTD="${ZSTD:-}"
TARGET="${TARGET:-}"
TARBALL_PATH="$1"
PATH_ARGS=()
EXTRA_ARGS=()
shift

if [[ "$TARGET" == *NULL ]]; then
    TARGET=
fi

if [[ -z "$TARBALL_PATH" ]]; then
    echo "TARBALL_PATH must be provided as an arg." >&2
    exit 1
fi

if [[ -e "$TARBALL_PATH" ]]; then
    echo "The TARBALL_PATH is not empty, exiting." >&2
    exit 1
fi

if [[ -z "$TARGET" && -z "${*}" ]]; then
    echo "TARGET/s must be provided using a bazel flag or as args." >&2
    exit 1
fi

if [[ -n "$TARGET" ]]; then
    PATH_ARGS+=(-C "$TARGET" .)
fi

for target in "$@"; do
    PATH_ARGS+=(-C "$target" .)
done

if [[ "$TARBALL_PATH" == *.zst ]]; then
    if [[ -z "$ZSTD" ]]; then
       echo "Zstd binary not set, exiting" >&2
       exit 1
    fi
    tar cf - "${EXTRA_ARGS[@]}" "${PATH_ARGS[@]}"  \
        | "$ZSTD" - -T0 -o "${TARBALL_PATH}"
else
    tar xf "$TARGET" -C "$TARBALL_PATH"
fi
