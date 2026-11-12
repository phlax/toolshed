#!/usr/bin/env bash
set -euo pipefail

# --- begin runfiles.bash initialization v3 ---
f=bazel_tools/tools/bash/runfiles/runfiles.bash
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null ||
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null ||
  source "$0.runfiles/$f" 2>/dev/null ||
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null ||
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null ||
  { echo >&2 "ERROR: cannot find $f"; exit 1; }
# --- end runfiles.bash initialization v3 ---

# Manifest-only runfiles may list tree children but not their directory.
jq_root() {
  local marker
  marker="$(rlocation "$1")"
  if [[ -z "$marker" || ! -e "$marker" ]]; then
    echo >&2 "jq launcher: cannot resolve module root marker '$1'"
    exit 1
  fi
  dirname "$marker"
}

@@COMMAND@@
