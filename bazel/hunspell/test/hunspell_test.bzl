"""Tests for the resolved hunspell toolchain."""

load("//hunspell:defs.bzl", "HUNSPELL_TOOLCHAIN_TYPE")

_SCRIPT = """#!/usr/bin/env bash
set -euo pipefail
runfiles="${TEST_SRCDIR:-$0.runfiles}"
exec "$runfiles/@@CHECK@@" "$runfiles/@@HUNSPELL@@" "$runfiles/@@DICT@@"
"""

def _runfile_path(ctx, file):
    if file.short_path.startswith("../"):
        return file.short_path[3:]
    return "%s/%s" % (ctx.workspace_name, file.short_path)

def _hunspell_toolchain_test_impl(ctx):
    info = ctx.toolchains[HUNSPELL_TOOLCHAIN_TYPE].hunspell
    script = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(
        script,
        _SCRIPT
            .replace("@@CHECK@@", _runfile_path(ctx, ctx.file.check))
            .replace("@@HUNSPELL@@", _runfile_path(ctx, info.hunspell))
            .replace("@@DICT@@", _runfile_path(ctx, info.dictionary)[:-len(".dic")]),
        is_executable = True,
    )
    runfiles = info.runfiles.merge(ctx.runfiles(files = [ctx.file.check]))
    return [DefaultInfo(executable = script, runfiles = runfiles)]

hunspell_toolchain_test = rule(
    implementation = _hunspell_toolchain_test_impl,
    attrs = {
        "check": attr.label(allow_single_file = True, mandatory = True),
    },
    test = True,
    toolchains = [HUNSPELL_TOOLCHAIN_TYPE],
)
