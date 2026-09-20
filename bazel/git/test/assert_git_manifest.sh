#!/bin/bash
set -euo pipefail

: "${TARBALL:?TARBALL must be set}"
: "${READELF:?READELF must be set}"
: "${GIT_VERSION:?GIT_VERSION must be set}"
: "${GLIBC_FLOOR:?GLIBC_FLOOR must be set}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

tar -xf "$TARBALL" -C "$tmp"

pkg_dir=$(find "$tmp" -mindepth 1 -maxdepth 1 -type d -name 'git-*' -print -quit)
test -n "$pkg_dir"

git_wrapper="$pkg_dir/bin/git"
git_bin="$pkg_dir/libexec/git-core/git"
git_remote_http="$pkg_dir/libexec/git-core/git-remote-http"
git_remote_https="$pkg_dir/libexec/git-core/git-remote-https"
git_templates="$pkg_dir/share/git-core/templates"
git_cacert="$pkg_dir/share/git-core/ca-certificates.crt"
home_dir="$tmp/home"
repo_dir="$tmp/repo"

for path in \
    "$pkg_dir/BUILD.bazel" \
    "$git_wrapper" \
    "$git_bin" \
    "$git_remote_http" \
    "$git_remote_https" \
    "$git_cacert" \
    "$git_templates"
do
    test -e "$path"
done

test "$(head -n 1 "$git_wrapper")" = "#!/bin/sh"
test -x "$git_wrapper"
test -x "$git_bin"
test -x "$git_remote_http"
if [ -L "$git_remote_https" ]; then
    test "$(readlink -f "$git_remote_https")" = "$git_remote_http"
else
    cmp -s "$git_remote_http" "$git_remote_https"
fi
test -d "$git_templates"
find "$git_templates" -type f -print -quit | grep -q .

cert_count=$(grep -c 'BEGIN CERTIFICATE' "$git_cacert")
test "$cert_count" -ge 100

version=$("$git_wrapper" --version 2>&1 || true)
test "${version%%$'\n'*}" = "git version $GIT_VERSION"

git_cmd() {
    env -i \
        HOME="$home_dir" \
        PATH="/usr/bin:/bin" \
        "$git_wrapper" "$@"
}

mkdir -p "$home_dir" "$repo_dir"

exec_path=$(git_cmd --exec-path)
test "$exec_path" = "$pkg_dir/libexec/git-core"

git_cmd init "$repo_dir" >/dev/null
test -f "$repo_dir/.git/hooks/applypatch-msg.sample"
git_cmd -C "$repo_dir" config user.name toolshed
git_cmd -C "$repo_dir" config user.email toolshed@example.com
printf 'hello\n' >"$repo_dir/README"
git_cmd -C "$repo_dir" add README
git_cmd -C "$repo_dir" commit -m initial >/dev/null
head_sha=$(git_cmd -C "$repo_dir" rev-parse HEAD)
printf '%s\n' "$head_sha" | grep -Eq '^[0-9a-f]{40}$'

check_needed() {
    binary=$1
    unexpected=$("$READELF" -d "$binary" | awk '/NEEDED/ { gsub(/\[|\]/, "", $NF); print $NF }' | grep -Ev '^(libc\.so\.6|libm\.so\.6|libpthread\.so\.0|libdl\.so\.2|librt\.so\.1|ld-linux[^[:space:]]*\.so(\.[0-9]+)*|libgcc_s\.so\.1)$' || true)
    if [ -n "$unexpected" ]; then
        echo "unexpected shared libraries for $binary:" >&2
        printf '%s\n' "$unexpected" >&2
        exit 1
    fi
}

check_glibc_floor() {
    binary=$1
    max_version=$("$READELF" -V "$binary" | awk '
        function version_gt(a, b,    ai, bi, an, bn, i, av, bv) {
            an = split(a, ai, ".")
            bn = split(b, bi, ".")
            for (i = 1; i <= an || i <= bn; i++) {
                av = (i in ai) ? ai[i] + 0 : 0
                bv = (i in bi) ? bi[i] + 0 : 0
                if (av > bv) {
                    return 1
                }
                if (av < bv) {
                    return 0
                }
            }
            return 0
        }
        {
            while (match($0, /GLIBC_[0-9]+(\.[0-9]+)+/)) {
                version = substr($0, RSTART + 6, RLENGTH - 6)
                if (max == "" || version_gt(version, max)) {
                    max = version
                }
                $0 = substr($0, RSTART + RLENGTH)
            }
        }
        END {
            if (max != "") {
                print max
            }
        }
    ')
    if [ -n "$max_version" ] && awk -v max="$max_version" -v floor="$GLIBC_FLOOR" '
        function version_gt(a, b,    ai, bi, an, bn, i, av, bv) {
            an = split(a, ai, ".")
            bn = split(b, bi, ".")
            for (i = 1; i <= an || i <= bn; i++) {
                av = (i in ai) ? ai[i] + 0 : 0
                bv = (i in bi) ? bi[i] + 0 : 0
                if (av > bv) {
                    return 1
                }
                if (av < bv) {
                    return 0
                }
            }
            return 0
        }
        BEGIN { exit version_gt(max, floor) ? 0 : 1 }
    '; then
        echo "FAIL: GLIBC requirement for $binary exceeds $GLIBC_FLOOR: $max_version" >&2
        exit 1
    fi
}

check_needed "$git_bin"
check_needed "$git_remote_http"
check_glibc_floor "$git_bin"
check_glibc_floor "$git_remote_http"

echo "PASS: git manifest checks passed"
