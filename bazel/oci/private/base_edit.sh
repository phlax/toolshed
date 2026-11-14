#!/usr/bin/env bash
#
# Edit the system files of an OCI base image, as package and user management tools would, without
# running anything in the image.
#
# Reads `/etc/{passwd,group,shadow,gshadow}` and `/var/lib/dpkg/status` from the layers of the
# image, adds the users and groups of the spec, and the dpkg status of the packages, and writes a
# layer with the edited files, and the new home directories.
#
# Usage: base_edit.sh <image layout> <spec json> <output tar> [<deb control tar>...]
#
# Requires `JQ` and `TAR` (bsdtar).

set -euo pipefail
# Fail on errors in command substitutions too, where bash supports it (>= 4.4). Failures that
# matter are also propagated explicitly.
shopt -s inherit_errexit 2> /dev/null || :

LAYOUT="$1"
SPEC="$2"
OUT="$3"
shift 3
CONTROLS=("$@")

# Allocation ranges, as `adduser` uses them for system users and groups.
FIRST_SYSTEM_ID=100
LAST_SYSTEM_ID=999

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ROOT="${WORK}/root"
mkdir -p "$ROOT"

fail () {
    echo "ERROR: $*" >&2
    exit 1
}

blob () {
    local digest="$1"
    echo "${LAYOUT}/blobs/${digest%%:*}/${digest#*:}"
}

# The image manifest. An index must have a single entry (ie a single platform image).
descriptor="$("$JQ" -c '.manifests | if length != 1 then error("expected a single manifest, got \(length)") else .[0] end' "${LAYOUT}/index.json")"
while [[ "$("$JQ" -r '.mediaType' <<< "$descriptor")" == *index* ]]; do
    descriptor="$("$JQ" -c '.manifests | if length != 1 then error("expected a single manifest, got \(length)") else .[0] end' "$(blob "$("$JQ" -r '.digest' <<< "$descriptor")")")"
done
MANIFEST="$(blob "$("$JQ" -r '.digest' <<< "$descriptor")")"

# Extract the files from the layers in order, so that each file is as it is in the image. For each
# layer, first apply its whiteouts (of the file, or of any of its parent directories, or opaque
# markers of its parent directories) to the files of the lower layers, then extract its files.
FILES=(etc/passwd etc/group etc/shadow etc/gshadow var/lib/dpkg/status)
# The paths in the image (for new homes and their parent directories): those of each layer, after
# applying its whiteouts to those of the lower layers.
PATHS="${WORK}/paths"
: > "$PATHS"

update_paths () {
    # update_paths <entries>: apply the whiteouts of the layer entries to the paths, and add the
    # other entries.
    if [[ ! -s "$1" ]]; then
        return
    fi
    awk '
        FNR == NR {
            n = split($0, parts, "/")
            name = parts[n]
            dir = (n > 1) ? substr($0, 1, length($0) - length(name)) : ""
            if (name == ".wh..wh..opq") {
                opaque[dir] = 1
            } else if (substr(name, 1, 4) == ".wh.") {
                deleted[dir substr(name, 5)] = 1
            } else {
                entries[$0] = 1
            }
            next
        }
        {
            for (path in deleted) {
                if ($0 == path || substr($0, 1, length(path) + 1) == path "/") next
            }
            for (dir in opaque) {
                if (dir == "" || substr($0, 1, length(dir)) == dir) next
            }
            print
        }
        END {
            for (entry in entries) print entry
        }' "$1" "$PATHS" | sort -u > "${PATHS}.new"
    mv "${PATHS}.new" "$PATHS"
}

whited_out () {
    # whited_out <entries> <file>: whether the layer entries delete the file of a lower layer
    local entries="$1" file="$2" path="" part
    local -a parts
    IFS=/ read -ra parts <<< "$file"
    for part in "${parts[@]}"; do
        if awk -v wh="${path}.wh.${part}" -v opq="${path}.wh..wh..opq" \
               '$0 == wh || $0 == opq {found = 1} END {exit !found}' \
               "$entries"; then
            return 0
        fi
        path="${path}${part}/"
    done
    return 1
}

while read -r digest; do
    layer="$(blob "$digest")"
    "$TAR" -tf "$layer" > "${WORK}/names"
    sed -e 's#^\./##' -e 's#/$##' "${WORK}/names" > "${WORK}/entries"
    update_paths "${WORK}/entries"
    # Only the files in this layer, by their names in it: bsdtar fails on a pattern that matches
    # nothing.
    INCLUDES=()
    for file in "${FILES[@]}"; do
        if whited_out "${WORK}/entries" "$file"; then
            rm -f "${ROOT}/${file}"
        fi
        while read -r name; do
            INCLUDES+=(--include "$name")
        done < <(awk -v file="$file" '$0 == file || $0 == "./" file' "${WORK}/names")
    done
    if [[ "${#INCLUDES[@]}" -gt 0 ]]; then
        "$TAR" -xf "$layer" -C "$ROOT" "${INCLUDES[@]}"
    fi
done < <("$JQ" -r '.layers[].digest' "$MANIFEST")

for file in "${FILES[@]}"; do
    # The files are read and written: only regular files (never follow a link out of the image root).
    if [[ -L "${ROOT}/${file}" ]] || [[ -e "${ROOT}/${file}" && ! -f "${ROOT}/${file}" ]]; then
        fail "${file} is not a regular file in the image"
    fi
    mkdir -p "$(dirname "${ROOT}/${file}")"
    touch "${ROOT}/${file}"
    chmod u+rw "${ROOT}/${file}"
done

free_id () {
    # free_id <file>: the first system id that is not used (3rd field) in the passwd or group file
    awk -F: -v first="$FIRST_SYSTEM_ID" -v last="$LAST_SYSTEM_ID" '
        {used[$3] = 1}
        END {
            for (id = first; id <= last; id++) {
                if (!(id in used)) {print id; exit 0}
            }
            exit 1
        }' "$1" || fail "No free system id in ${1#"${ROOT}/"}"
}

has_entry () {
    # has_entry <file> <name>: whether the passwd or group file has an entry of the name
    awk -F: -v name="$2" '$1 == name {found = 1} END {exit !found}' "$1"
}

id_used () {
    # id_used <file> <id>: whether the passwd or group file has an entry with the id
    awk -F: -v id="$2" '$3 == id {found = 1} END {exit !found}' "$1"
}

# Days since the epoch for new shadow entries. Use those of `root`, so that the output only depends
# on the image.
LASTCHG="$(awk -F: '$1 == "root" {print $3}' "${ROOT}/etc/shadow")"

add_group () {
    # add_group <name> [<gid>]
    local name="$1" gid="${2:-}"
    if has_entry "${ROOT}/etc/group" "$name"; then
        fail "Group ${name} exists in the image"
    fi
    if [[ -z "$gid" ]]; then
        gid="$(free_id "${ROOT}/etc/group")" || return 1
    elif id_used "${ROOT}/etc/group" "$gid"; then
        fail "Group id ${gid} (${name}) is used in the image"
    fi
    echo "${name}:x:${gid}:" >> "${ROOT}/etc/group"
    echo "${name}:!::" >> "${ROOT}/etc/gshadow"
    echo "$gid"
}

group_id () {
    # group_id <name>
    awk -F: -v name="$1" '$1 == name {print $3}' "${ROOT}/etc/group"
}

# Groups
while read -r group; do
    add_group "$("$JQ" -r '.name' <<< "$group")" "$("$JQ" -r '.gid // empty' <<< "$group")" > /dev/null
done < <("$JQ" -c '.groups[]' "$SPEC")

# Users. A user with `"group": true` gets a group of the same name, with the same id if it is free
# (as `adduser --system --group`).
HOMES=()
while read -r user; do
    name="$("$JQ" -r '.name' <<< "$user")"
    uid="$("$JQ" -r '.uid // empty' <<< "$user")"
    home="$("$JQ" -r '.home // "/home/\(.name)"' <<< "$user")"
    shell="$("$JQ" -r '.shell // "/usr/sbin/nologin"' <<< "$user")"
    gecos="$("$JQ" -r '.gecos // ""' <<< "$user")"
    if has_entry "${ROOT}/etc/passwd" "$name"; then
        fail "User ${name} exists in the image"
    fi
    if [[ "$home" != /* || "$home" == "/" ]]; then
        fail "Home of user ${name} must be an absolute path (other than /): ${home}"
    fi
    if [[ -z "$uid" ]]; then
        uid="$(free_id "${ROOT}/etc/passwd")" || exit 1
    elif id_used "${ROOT}/etc/passwd" "$uid"; then
        fail "User id ${uid} (${name}) is used in the image"
    fi
    if [[ "$("$JQ" -r '.group // false' <<< "$user")" == "true" ]]; then
        if id_used "${ROOT}/etc/group" "$uid"; then
            gid="$(add_group "$name")" || exit 1
        else
            gid="$(add_group "$name" "$uid")" || exit 1
        fi
    else
        gid="$("$JQ" -r '.gid // empty' <<< "$user")"
        if [[ -z "$gid" ]]; then
            gid="$(group_id "$("$JQ" -r '.primary_group // "nogroup"' <<< "$user")")"
        fi
        [[ -n "$gid" ]] || fail "No group for user ${name}"
    fi
    echo "${name}:x:${uid}:${gid}:${gecos}:${home}:${shell}" >> "${ROOT}/etc/passwd"
    echo "${name}:*:${LASTCHG}:0:99999:7:::" >> "${ROOT}/etc/shadow"
    if [[ "$("$JQ" -r 'if has("create_home") then .create_home else true end' <<< "$user")" == "true" ]]; then
        HOMES+=("${home}:${uid}:${gid}:$("$JQ" -r '.home_mode // "0750"' <<< "$user")")
    fi
done < <("$JQ" -c '.users[]' "$SPEC")

# dpkg status: add (or replace) the entry of each package, from its control file, as installed.
STATUS=0
for control in "${CONTROLS[@]}"; do
    STATUS=1
    mkdir -p "${WORK}/control"
    name="$("$TAR" -tf "$control" | awk '($0 == "control" || $0 == "./control") && !found {print; found = 1}')"
    [[ -n "$name" ]] || fail "No control file in ${control}"
    "$TAR" -xf "$control" -C "${WORK}/control" --include "$name"
    if [[ -L "${WORK}/control/control" || ! -f "${WORK}/control/control" ]]; then
        fail "The control file of ${control} is not a regular file"
    fi
    entry="$(awk '{print} /^Package:/ {print "Status: install ok installed"}' "${WORK}/control/control" | sed -e '/^$/d')"
    package="$(awk '/^Package:/ {print $2}' <<< "$entry")"
    arch="$(awk '/^Architecture:/ {print $2}' <<< "$entry")"
    awk -v RS= -v ORS='\n\n' -v package="$package" -v arch="$arch" '
        {
            p = ""; a = ""
            n = split($0, lines, "\n")
            for (i = 1; i <= n; i++) {
                if (lines[i] ~ /^Package: /) p = substr(lines[i], 10)
                if (lines[i] ~ /^Architecture: /) a = substr(lines[i], 15)
            }
            if (p == package && (a == arch || a == "all" || arch == "all")) next
            print
        }' "${ROOT}/var/lib/dpkg/status" > "${WORK}/status"
    printf '%s\n\n' "$entry" >> "${WORK}/status"
    mv "${WORK}/status" "${ROOT}/var/lib/dpkg/status"
    rm -rf "${WORK}/control"
done

# The layer
SHADOW_GID="$(group_id shadow)"
SHADOW_GID="${SHADOW_GID:-0}"
MTREE="${WORK}/mtree"
{
    echo "#mtree"
    if [[ "$("$JQ" '(.users | length) + (.groups | length)' "$SPEC")" != "0" ]]; then
        echo "./etc type=dir uid=0 gid=0 mode=0755 time=0"
        echo "./etc/passwd type=file uid=0 gid=0 mode=0644 time=0 contents=${ROOT}/etc/passwd"
        echo "./etc/group type=file uid=0 gid=0 mode=0644 time=0 contents=${ROOT}/etc/group"
        echo "./etc/shadow type=file uid=0 gid=${SHADOW_GID} mode=0640 time=0 contents=${ROOT}/etc/shadow"
        echo "./etc/gshadow type=file uid=0 gid=${SHADOW_GID} mode=0640 time=0 contents=${ROOT}/etc/gshadow"
    fi
    if [[ "$STATUS" == 1 ]]; then
        echo "./var type=dir uid=0 gid=0 mode=0755 time=0"
        echo "./var/lib type=dir uid=0 gid=0 mode=0755 time=0"
        echo "./var/lib/dpkg type=dir uid=0 gid=0 mode=0755 time=0"
        echo "./var/lib/dpkg/status type=file uid=0 gid=0 mode=0644 time=0 contents=${ROOT}/var/lib/dpkg/status"
    fi
    # Homes that are in the image are left as they are (as `adduser` does).
    for entry in "${HOMES[@]}"; do
        IFS=: read -r home uid gid mode <<< "$entry"
        if ! awk -v path="${home#/}" '$0 == path {found = 1} END {exit !found}' "$PATHS"; then
            echo ".${home} type=dir uid=${uid} gid=${gid} mode=${mode} time=0"
        fi
    done
    # Parent directories of the homes that are not in the image (or another home), as root
    # directories. Those in the image are left as they are.
    for entry in "${HOMES[@]}"; do
        IFS=: read -r home _ <<< "$entry"
        parent="$(dirname "$home")"
        while [[ "$parent" != "/" ]]; do
            if ! awk -v path="${parent#/}" '$0 == path {found = 1} END {exit !found}' "$PATHS" \
                    && ! printf '%s\n' "${HOMES[@]}" | cut -d: -f1 \
                        | awk -v path="$parent" '$0 == path {found = 1} END {exit !found}'; then
                echo ".${parent} type=dir uid=0 gid=0 mode=0755 time=0"
            fi
            parent="$(dirname "$parent")"
        done
    done
} | sort -u -k1,1 > "$MTREE"

"$TAR" --create --file "$OUT" --format=pax "@${MTREE}"
