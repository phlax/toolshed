#!/usr/bin/env bash

set -e -o pipefail


MODULE_BAZEL="bazel/MODULE.bazel"
JQ_MODULE_BAZEL="jq/MODULE.bazel"

# `jq/` is versioned and released together with `envoy_toolshed` (see
# `jq/README.md`), so its own `module()` version and the `envoy_toolshed_jq`
# `bazel_dep` pin in `bazel/MODULE.bazel` are bumped in lockstep here.
echo "\$ sed -i '/^module(/,/^)/s/version = \\\"[^\\\"]*\\\"/version = \\\"${NEXT_VERSION}\\\"/' ${MODULE_BAZEL}" >> "$TMP_OUTPUT"
echo "\$ sed -i '/^module(/,/^)/s/version = \\\"[^\\\"]*\\\"/version = \\\"${NEXT_VERSION}\\\"/' ${JQ_MODULE_BAZEL}" >> "$TMP_OUTPUT"
echo "\$ sed -i '/name = \\\"envoy_toolshed_jq\\\"/s/version = \\\"[^\\\"]*\\\"/version = \\\"${NEXT_VERSION}\\\"/' ${MODULE_BAZEL}" >> "$TMP_OUTPUT"
if [[ -n "$DEBUG" ]]; then
    echo "\$ sed -i '/^module(/,/^)/s/version = \\\"[^\\\"]*\\\"/version = \\\"${NEXT_VERSION}\\\"/' ${MODULE_BAZEL}" >&2
    echo "\$ sed -i '/^module(/,/^)/s/version = \\\"[^\\\"]*\\\"/version = \\\"${NEXT_VERSION}\\\"/' ${JQ_MODULE_BAZEL}" >&2
    echo "\$ sed -i '/name = \\\"envoy_toolshed_jq\\\"/s/version = \\\"[^\\\"]*\\\"/version = \\\"${NEXT_VERSION}\\\"/' ${MODULE_BAZEL}" >&2
fi
sed -i "/^module(/,/^)/s/version = \"[^\"]*\"/version = \"${NEXT_VERSION}\"/" "${MODULE_BAZEL}"
sed -i "/^module(/,/^)/s/version = \"[^\"]*\"/version = \"${NEXT_VERSION}\"/" "${JQ_MODULE_BAZEL}"
sed -i "/name = \"envoy_toolshed_jq\"/s/version = \"[^\"]*\"/version = \"${NEXT_VERSION}\"/" "${MODULE_BAZEL}"
echo "${MODULE_BAZEL}"
echo "${JQ_MODULE_BAZEL}"
