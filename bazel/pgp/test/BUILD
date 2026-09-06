load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("//pgp:defs.bzl", "pgp_sign_changes_file", "pgp_sign_checksums", "pgp_sign_cleartext", "pgp_sign_detached", "pgp_toolchain")
load(":sign_test.bzl", "args_test", "env_test", "execution_requirements_test", "no_passphrase_test", "relative_passphrase_test")

# Stub signer/toolchain for the analysis tests. Real signing requires a
# registered `sq` toolchain, see //pgp:extensions.bzl.
sh_binary(
    name = "stub_signer",
    srcs = ["stub_signer.sh"],
)

pgp_toolchain(
    name = "stub_signer_toolchain",
    signer = ":stub_signer",
)

toolchain(
    name = "stub_toolchain",
    toolchain = ":stub_signer_toolchain",
    toolchain_type = "//pgp:toolchain_type",
)

# Placeholder key/inputs, checked in statically. No key material is ever
# committed - `example_key.pgp` is the literal text `NOT A KEY`, and the
# integration test (`signer_test`) generates a real (encrypted) key at test
# time.
exports_files(["fixtures/example_key.pgp"])

# Example signing targets. They are `manual` because building them requires
# `--@envoy_toolshed//pgp:passphrase_path` and a real signer toolchain.
pgp_sign_detached(
    name = "example_detached",
    src = "fixtures/example.txt",
    key = "fixtures/example_key.pgp",
    tags = ["manual"],
)

pgp_sign_cleartext(
    name = "example_cleartext",
    src = "fixtures/example.txt",
    key = "fixtures/example_key.pgp",
    out = "example.txt.cleartext.asc",
    tags = ["manual"],
)

pgp_sign_checksums(
    name = "example_checksums",
    srcs = [
        "fixtures/example.changes",
        "fixtures/example.txt",
    ],
    key = "fixtures/example_key.pgp",
    tags = ["manual"],
)

pgp_sign_changes_file(
    name = "example_deb_changes",
    changes = "fixtures/example.changes",
    key = "fixtures/example_key.pgp",
    tags = ["manual"],
)

execution_requirements_test(
    name = "execution_requirements_test",
)

env_test(
    name = "env_test",
    target_under_test = ":example_detached",
)

args_test(
    name = "detached_args_test",
    mode = "detached",
    target_under_test = ":example_detached",
)

args_test(
    name = "cleartext_args_test",
    mode = "cleartext",
    target_under_test = ":example_cleartext",
)

args_test(
    name = "checksums_args_test",
    mode = "cleartext",
    target_under_test = ":example_checksums",
)

args_test(
    name = "deb_changes_args_test",
    mode = "cleartext",
    target_under_test = ":example_deb_changes",
)

no_passphrase_test(
    name = "no_passphrase_test",
    target_under_test = ":example_detached",
)

relative_passphrase_test(
    name = "relative_passphrase_test",
    target_under_test = ":example_detached",
)

# Audits captured `bazel aquery` output. This is a unit test of the audit
# script itself: `fixtures/audit.json` is the real aquery output for the
# example signing targets in this package (must pass); the broken variants
# (a removed execution requirement, a leaked environment variable, key
# material as an action input, a passphrase on the command line) are derived
# from it with `jq` at test time rather than committed, so this package does
# not carry several ~1000-line JSON fixtures.
#
# Run the same script against your own targets with:
#
#   bazel run //pgp/test:audit -- //your/targets/...
#
# See `//pgp/test:live_audit` for the live counterpart that actually
# re-invokes `bazel aquery` against this package's real dependency graph.
sh_test(
    name = "audit_test",
    size = "small",
    srcs = ["audit_fixtures_test.sh"],
    data = [
        "audit_test.sh",
        "fixtures/audit.json",
        "@jq_toolchains//:resolved_toolchain",
    ],
    env = {
        "JQ_BIN": "$(JQ_BIN)",
    },
    toolchains = ["@jq_toolchains//:resolved_toolchain"],
)

sh_binary(
    name = "audit",
    srcs = ["audit_test.sh"],
    visibility = ["//visibility:public"],
)

# Runs the audit against a real `bazel aquery` of this package's example
# targets, rather than captured JSON (see `//pgp/test:audit_test` for that).
# `manual`: it shells out to `bazel`, so it cannot run as a sandboxed test -
# invoke explicitly with `bazel run //pgp/test:live_audit`, including in CI.
sh_binary(
    name = "live_audit",
    srcs = ["live_audit.sh"],
    tags = ["manual"],
)

# Signs with a real `sq`, if one is available (`SQ` or `$PATH`), and asserts
# that unencrypted keys are rejected. Skipped when `sq` is not installed.
sh_test(
    name = "signer_test",
    size = "medium",
    srcs = ["signer_test.sh"],
    data = ["//pgp/private:signer.sh"],
)
