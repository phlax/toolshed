"""Build and package the registry git source target for Linux toolchains."""

load("@aspect_bazel_lib//lib:tar.bzl", "mtree_mutate", "mtree_spec", "tar")
load("@rules_pkg//pkg:providers.bzl", "PackageFilesInfo")
load("//:versions.bzl", "VERSIONS")

_PLATFORMS = {
    "Linux-X64": "@toolchains_llvm//platforms:linux-x86_64",
    "Linux-ARM64": "@toolchains_llvm//platforms:linux-aarch64",
}

def _git_transition_impl(settings, attr):
    return {
        "//command_line_option:platforms": [_PLATFORMS[attr.platform]],
        "@curl//:ssl_lib": "openssl",
    }

_git_transition = transition(
    implementation = _git_transition_impl,
    inputs = [],
    outputs = [
        "//command_line_option:platforms",
        "@curl//:ssl_lib",
    ],
)

def _strip_binary(ctx, src, out, progress_message):
    ctx.actions.run_shell(
        inputs = [src],
        tools = [ctx.executable.stripper],
        outputs = [out],
        command = "mkdir -p $(dirname \"$3\") && \"$2\" -o \"$3\" \"$1\"",
        arguments = [src.path, ctx.executable.stripper.path, out.path],
        mnemonic = "GitStrip",
        progress_message = progress_message,
    )

def _copy_file(ctx, src, out, progress_message):
    ctx.actions.run_shell(
        inputs = [src],
        outputs = [out],
        command = "mkdir -p $(dirname \"$2\") && cp -f \"$1\" \"$2\"",
        arguments = [src.path, out.path],
        mnemonic = "GitCopyFile",
        progress_message = progress_message,
    )

def _template_dest(src):
    parts = src.short_path.split("/templates/", 1)
    if len(parts) != 2:
        fail("template path missing /templates/: %s" % src.short_path)
    return "share/git-core/templates/" + parts[1]

def _git_files_impl(ctx):
    package_dir = "git-%s-%s" % (VERSIONS["git"], ctx.attr.platform)
    git = ctx.attr.git[0][DefaultInfo].files.to_list()[0]
    git_remote_http = ctx.attr.git_remote_http[0][DefaultInfo].files.to_list()[0]
    templates = sorted(ctx.attr.templates[0][DefaultInfo].files.to_list(), key = lambda f: f.short_path)
    cacert = ctx.file.cacert

    git_wrapper = ctx.actions.declare_file(package_dir + "/bin/git")
    git_out = ctx.actions.declare_file(package_dir + "/libexec/git-core/git")
    git_remote_http_out = ctx.actions.declare_file(package_dir + "/libexec/git-core/git-remote-http")
    git_remote_https_out = ctx.actions.declare_file(package_dir + "/libexec/git-core/git-remote-https")
    cacert_out = ctx.actions.declare_file(package_dir + "/share/git-core/ca-certificates.crt")
    template_outs = []

    _strip_binary(ctx, git, git_out, "Stripping git for " + ctx.attr.platform)
    _strip_binary(ctx, git_remote_http, git_remote_http_out, "Stripping git-remote-http for " + ctx.attr.platform)
    _copy_file(ctx, cacert, cacert_out, "Copying cacert for " + ctx.attr.platform)
    for src in templates:
        rel = _template_dest(src)
        out = ctx.actions.declare_file(package_dir + "/" + rel)
        _copy_file(ctx, src, out, "Copying template %s for %s" % (rel, ctx.attr.platform))
        template_outs.append((rel, out))
    _copy_file(ctx, git_remote_http_out, git_remote_https_out, "Copying git-remote-https for " + ctx.attr.platform)
    ctx.actions.write(
        output = git_wrapper,
        content = """#!/bin/sh
self=$0
case "$self" in
    /*) ;;
    *) self="$(pwd)/$self" ;;
esac
while [ -L "$self" ]; do
    link="$(readlink "$self")"
    case "$link" in
        /*) self="$link" ;;
        *) self="$(dirname "$self")/$link" ;;
    esac
done
here="$(CDPATH= cd "$(dirname "$self")/.." && pwd)"
export GIT_EXEC_PATH="$here/libexec/git-core"
export GIT_TEMPLATE_DIR="$here/share/git-core/templates"
: "${GIT_SSL_CAINFO:=${TOOLSHED_CA_BUNDLE:-$here/share/git-core/ca-certificates.crt}}"
export GIT_SSL_CAINFO
export SSL_CERT_FILE="$GIT_SSL_CAINFO"
exec "$GIT_EXEC_PATH/git" "$@"
""",
        is_executable = True,
    )

    dest_src_map = {
        "bin/git": git_wrapper,
        "libexec/git-core/git": git_out,
        "libexec/git-core/git-remote-http": git_remote_http_out,
        "libexec/git-core/git-remote-https": git_remote_https_out,
        "share/git-core/ca-certificates.crt": cacert_out,
    }
    for rel, out in template_outs:
        dest_src_map[rel] = out

    return [
        DefaultInfo(files = depset([git_wrapper, git_out, git_remote_http_out, git_remote_https_out, cacert_out] + [out for _, out in template_outs])),
        PackageFilesInfo(dest_src_map = dest_src_map, attributes = {}),
    ]

git_files = rule(
    implementation = _git_files_impl,
    attrs = {
        "git": attr.label(
            mandatory = True,
            executable = True,
            cfg = _git_transition,
        ),
        "git_remote_http": attr.label(
            mandatory = True,
            executable = True,
            cfg = _git_transition,
        ),
        "cacert": attr.label(
            default = "@cacert//file",
            allow_single_file = True,
        ),
        "templates": attr.label(
            mandatory = True,
            cfg = _git_transition,
        ),
        "platform": attr.string(mandatory = True, values = _PLATFORMS.keys()),
        "stripper": attr.label(
            mandatory = True,
            executable = True,
            cfg = "exec",
            allow_single_file = True,
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)

def git_package(name, platform, stripper):
    package_dir = "git-%s-%s" % (VERSIONS["git"], platform)
    files = name + "_files"
    build = name + "_build"
    native.genrule(
        name = build,
        outs = [package_dir + "/BUILD.bazel"],
        cmd = """cat >"$@" <<'EOF'
exports_files(glob(["**"]))
filegroup(name = "git", srcs = ["bin/git"], visibility = ["//visibility:public"])
filegroup(name = "runtime", srcs = glob(["libexec/**", "share/**"]), visibility = ["//visibility:public"])
EOF""",
        tags = ["manual"],
    )
    git_files(
        name = files,
        git = "@git//:git",
        git_remote_http = "@git//:git-remote-http",
        platform = platform,
        stripper = stripper,
        tags = ["manual"],
        templates = "@git//:templates",
    )
    mtree_spec(
        name = name + "_mtree_src",
        srcs = [":" + files, ":" + build],
        tags = ["manual"],
    )
    mtree_mutate(
        name = name + "_mtree",
        mtree = ":" + name + "_mtree_src",
        package_dir = package_dir,
        preserve_symlinks = True,
        srcs = [":" + files, ":" + build],
        strip_prefix = "git/" + package_dir,
        tags = ["manual"],
    )
    tar(
        name = name,
        args = ["--options=zstd:compression-level=19,zstd:threads=4"],
        compress = "zstd",
        exec_properties = {"Pool": "linux_x64_xlarge"},
        mtree = ":" + name + "_mtree",
        out = package_dir + ".tar.zst",
        srcs = [":" + files, ":" + build],
        tags = ["manual"],
    )
