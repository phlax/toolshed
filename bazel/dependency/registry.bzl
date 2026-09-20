load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

def _repo_registry_impl(ctx):
    repo = ctx.attr.repo[BuildSettingInfo].value
    url = ctx.attr.url[BuildSettingInfo].value
    out = ctx.actions.declare_file(ctx.label.name + ".txt")
    ctx.actions.run_shell(
        outputs = [out],
        command = """
set -euo pipefail
COMMIT=$(git ls-remote --exit-code "$1" "refs/heads/$2" | cut -f1)
echo "$3/$COMMIT" > "$4"
""",
        arguments = [repo, ctx.attr.ref, url, out.path],
        mnemonic = "RepoVersions",
        progress_message = "Resolving %s@%s" % (repo, ctx.attr.ref),
        # Non-hermetic: needs network and host git, and must never be cached.
        use_default_shell_env = True,
        execution_requirements = {
            "local": "1",
            "no-cache": "1",
            "no-remote": "1",
            "no-sandbox": "1",
            "requires-network": "1",
        },
    )
    return [DefaultInfo(files = depset([out]))]

repo_registry = rule(
    implementation = _repo_registry_impl,
    attrs = {
        "repo": attr.label(mandatory = True),
        "ref": attr.string(default = "main"),
        "url": attr.label(mandatory = True),
    },
)

def _registry_bazelrc_impl(ctx):
    prefix = ctx.attr.url[BuildSettingInfo].value
    out = ctx.actions.declare_file(ctx.label.name + "/" + ctx.file.bazelrc.basename)
    ctx.actions.run_shell(
        inputs = [ctx.file.bazelrc, ctx.file.registry],
        outputs = [out],
        arguments = [ctx.file.bazelrc.path, ctx.file.registry.path, prefix, out.path],
        command = """
set -euo pipefail
src="$1"; resolved="$(cat "$2")"; prefix="$3"; out="$4"
if ! grep -qE "^[a-z:]* --registry=${prefix}/[0-9a-f]+\\s*$" "$src"; then
    echo "No '--registry=${prefix}/<sha>' line found in ${src}" >&2
    exit 1
fi
sed -E "s|^([a-z:]* --registry=)${prefix}/[0-9a-f]+\\s*$|\\1${resolved}|" "$src" > "$out"
""",
        mnemonic = "RegistryBazelrc",
    )
    return [DefaultInfo(files = depset([out]))]

registry_bazelrc = rule(
    implementation = _registry_bazelrc_impl,
    attrs = {
        "bazelrc": attr.label(mandatory = True, allow_single_file = True),
        "registry": attr.label(mandatory = True, allow_single_file = True),
        "url": attr.label(mandatory = True, providers = [BuildSettingInfo]),
    },
)
