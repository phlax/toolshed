#!/usr/bin/env bash

# Minimal bazel smoke-test for a bazel-registry module version.
#
# Handles two presubmit.yml shapes:
#
# Shape A — has `bcr_test_module` with a `module_path`:
#   The version ships a real consumer/test module (e.g. overlay/test/MODULE.bazel)
#   that wires the module under test via `local_path_override`.  We `cd` into
#   that test module, point it at the local registry, and build the first task's
#   declared targets.
#
# Shape B — bare top-level `matrix:`/`tasks:` with no `bcr_test_module`:
#   Targets are like `@hyperscan//:hyperscan` — there is no test module.  We
#   generate a minimal throwaway consumer workspace in /tmp that declares
#   `bazel_dep(name = "<module>", version = "<MODULE_VERSION>",
#              repo_name = "mod_under_test")` and points it at the local registry.
#   Target labels `@<module>//` are rewritten to `@mod_under_test//`.
#
# Environment variables (required):
#   MODULE           – module name (e.g. "librdkafka")
#   MODULE_VERSION   – versioned directory name (e.g. "2.6.0.envoy")
#   MODULES_ROOT     – registry root relative to GITHUB_WORKSPACE (e.g. "bazel-registry")
#   GITHUB_WORKSPACE – absolute path to workspace root (set by GitHub Actions)
#
# Opt-out: place a file named "no-bazel-test" in the version directory to skip.

set -e -o pipefail

REGISTRY_ROOT="${GITHUB_WORKSPACE}/${MODULES_ROOT}"
VERSION_DIR="${REGISTRY_ROOT}/modules/${MODULE}/${MODULE_VERSION}"

# ── Opt-out check ────────────────────────────────────────────────────────────
if [[ -f "${VERSION_DIR}/no-bazel-test" ]]; then
    echo "Skipping bazel test for ${MODULE}@${MODULE_VERSION} (no-bazel-test marker present)" >&2
    exit 0
fi

PRESUBMIT="${VERSION_DIR}/presubmit.yml"
if [[ ! -f "${PRESUBMIT}" ]]; then
    echo "::error::No presubmit.yml for ${MODULE}@${MODULE_VERSION} — cannot run module test" >&2
    exit 1
fi

# ── Parse presubmit.yml via yq→json + jq (avoids mikefarah-yq quirks) ───────
PRESUBMIT_JSON=$(yq -o=json "${PRESUBMIT}")

# Determine shape: does presubmit have a bcr_test_module.module_path?
MODULE_PATH=$(echo "${PRESUBMIT_JSON}" | jq -r '.bcr_test_module.module_path // ""')

# Extract first task's build_flags and build_targets.
# Try bcr_test_module.tasks first (Shape A), fall back to top-level tasks (Shape B).
FIRST_TASK_JSON=$(echo "${PRESUBMIT_JSON}" | jq -c '
  (.bcr_test_module.tasks // .tasks)
  | to_entries[0].value
')

readarray -t BUILD_FLAGS < <(echo "${FIRST_TASK_JSON}" | jq -r '(.build_flags // [])[]')
readarray -t BUILD_TARGETS < <(echo "${FIRST_TASK_JSON}" | jq -r '(.build_targets // [])[]')

echo "Registry: ${REGISTRY_ROOT}" >&2

# ── Shape A: test module ships inside the version / overlay ──────────────────
if [[ -n "${MODULE_PATH}" ]]; then
    TEST_MODULE_DIR="${VERSION_DIR}/${MODULE_PATH}"
    if [[ ! -f "${TEST_MODULE_DIR}/MODULE.bazel" ]]; then
        # Overlay-based layout: overlay/<module_path>/MODULE.bazel
        if [[ -f "${VERSION_DIR}/overlay/${MODULE_PATH}/MODULE.bazel" ]]; then
            TEST_MODULE_DIR="${VERSION_DIR}/overlay/${MODULE_PATH}"
        else
            echo "::error::No MODULE.bazel found for test module at ${TEST_MODULE_DIR}" >&2
            exit 1
        fi
    fi

    echo "Testing ${MODULE}@${MODULE_VERSION} via test module ${TEST_MODULE_DIR}" >&2

    cat > "${TEST_MODULE_DIR}/.bazelrc" <<EOF
common --registry=file://${REGISTRY_ROOT}
common --registry=https://bcr.bazel.build
EOF

    if [[ ${#BUILD_TARGETS[@]} -eq 0 ]]; then
        BUILD_TARGETS=("//...")
    fi

    echo "Running: bazel build ${BUILD_FLAGS[*]} ${BUILD_TARGETS[*]}" >&2
    cd "${TEST_MODULE_DIR}"
    bazel build "${BUILD_FLAGS[@]}" "${BUILD_TARGETS[@]}"

# ── Shape B: no test module — generate a minimal consumer workspace in /tmp ──
else
    echo "Testing ${MODULE}@${MODULE_VERSION} via generated consumer (Shape B)" >&2

    if [[ ${#BUILD_TARGETS[@]} -eq 0 ]]; then
        echo "::error::No build_targets found in presubmit.yml for ${MODULE}@${MODULE_VERSION}" >&2
        exit 1
    fi

    CONSUMER_DIR=$(mktemp -d /tmp/bazel-consumer-XXXXXX)
    trap 'rm -rf "${CONSUMER_DIR}"' EXIT

    cat > "${CONSUMER_DIR}/MODULE.bazel" <<EOF
module(name = "consumer_test")
bazel_dep(name = "${MODULE}", version = "${MODULE_VERSION}", repo_name = "mod_under_test")
EOF

    cat > "${CONSUMER_DIR}/.bazelrc" <<EOF
common --registry=file://${REGISTRY_ROOT}
common --registry=https://bcr.bazel.build
EOF

    # Rewrite @<module>// labels to @mod_under_test// so they resolve correctly.
    REWRITTEN_TARGETS=()
    for t in "${BUILD_TARGETS[@]}"; do
        REWRITTEN_TARGETS+=("${t//@${MODULE}\/\///@mod_under_test//}")
    done

    echo "Running: bazel build ${BUILD_FLAGS[*]} ${REWRITTEN_TARGETS[*]}" >&2
    cd "${CONSUMER_DIR}"
    bazel build "${BUILD_FLAGS[@]}" "${REWRITTEN_TARGETS[@]}"
fi

echo "✓ ${MODULE}@${MODULE_VERSION} – patches/overlays applied and module builds" >&2
