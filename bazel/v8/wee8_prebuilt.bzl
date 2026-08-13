"""Repository rules for prebuilt V8 wee8 bundles."""

load("//:versions.bzl", "V8_VERSION", "VERSIONS")

_WEE8_BUILD = """\
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "headers",
    srcs = glob(
        [
            "include/**",
            "third_party/**/*.h",
            "third_party/**/*.hh",
            "src/**/*.h",
        ],
    ),
)

filegroup(
    name = "libs",
    srcs = ["lib/libwee8.a"],
)

cc_library(
    name = "wee8",
    srcs = ["lib/libwee8.a"],
    hdrs = [":headers"],
    includes = [
        ".",
        "include",
    ],
    linkstatic = True,
    # wee8_package excludes abseil/icu archives from libwee8.a; consumers must
    # link those separately.
    deps = [
        "@abseil-cpp//absl/container:btree",
        "@abseil-cpp//absl/container:flat_hash_map",
        "@abseil-cpp//absl/container:flat_hash_set",
        "@abseil-cpp//absl/functional:overload",
        "@abseil-cpp//absl/synchronization",
        "@icu//:icu",
    ],
)
"""

def _wee8_prebuilt_impl(ctx):
    """Implementation for wee8 prebuilt repository rule."""
    ctx.download_and_extract(
        url = "https://github.com/envoyproxy/toolshed/releases/download/bins-v{version}/v8-wee8-{v8_version}-linux-{arch}.tar.xz".format(
            version = ctx.attr.version,
            v8_version = V8_VERSION,
            arch = ctx.attr.arch,
        ),
        sha256 = ctx.attr.sha256,
    )

    ctx.file("BUILD.bazel", _WEE8_BUILD)

wee8_prebuilt = repository_rule(
    implementation = _wee8_prebuilt_impl,
    attrs = {
        "version": attr.string(
            mandatory = True,
            doc = "Release version to download",
        ),
        "sha256": attr.string(
            mandatory = True,
            doc = "SHA256 hash of the wee8 archive.",
        ),
        "arch": attr.string(
            mandatory = True,
            values = ["x86_64", "aarch64"],
            doc = "Architecture to target",
        ),
    },
    doc = "Downloads prebuilt wee8 bundles for cross-compilation",
)

def setup_wee8_prebuilt(
        x86_64_version = None,
        x86_64_sha256 = None,
        aarch64_version = None,
        aarch64_sha256 = None):
    """Setup function for WORKSPACE and bzlmod."""
    wee8_prebuilt(
        name = "wee8_prebuilt_x86_64",
        version = x86_64_version or VERSIONS["bins_release"],
        sha256 = x86_64_sha256 or VERSIONS["wee8_sha256"]["x86_64"],
        arch = "x86_64",
    )

    wee8_prebuilt(
        name = "wee8_prebuilt_aarch64",
        version = aarch64_version or VERSIONS["bins_release"],
        sha256 = aarch64_sha256 or VERSIONS["wee8_sha256"]["aarch64"],
        arch = "aarch64",
    )

def _icu_workspace_stub_impl(ctx):
    """Creates a stub @icu repository for WORKSPACE analysis compatibility.

    The stub declares the :icu target so that @wee8_prebuilt_*//:wee8 can be
    analysed in workspace mode.  It does not provide a real ICU implementation;
    the wee8 smoke test is tagged manual and only exercised via the bzlmod leg
    of the CI test job, where the real @icu module is available.
    """
    ctx.file("BUILD.bazel", """package(default_visibility = ["//visibility:public"])

cc_library(name = "icu")
""")

_icu_workspace_stub = repository_rule(
    implementation = _icu_workspace_stub_impl,
    doc = "Stub @icu repository for WORKSPACE-mode analysis of wee8_prebuilt targets.",
)

def _abseil_cpp_workspace_stub_impl(ctx):
    """Creates a stub @abseil-cpp repository for WORKSPACE analysis compatibility."""
    ctx.file("BUILD.bazel", "")
    ctx.file("absl/container/BUILD.bazel", """package(default_visibility = ["//visibility:public"])

cc_library(name = "btree")
cc_library(name = "flat_hash_map")
cc_library(name = "flat_hash_set")
""")
    ctx.file("absl/functional/BUILD.bazel", """package(default_visibility = ["//visibility:public"])

cc_library(name = "overload")
""")
    ctx.file("absl/synchronization/BUILD.bazel", """package(default_visibility = ["//visibility:public"])

cc_library(name = "synchronization")
""")

_abseil_cpp_workspace_stub = repository_rule(
    implementation = _abseil_cpp_workspace_stub_impl,
    doc = "Stub @abseil-cpp repository for WORKSPACE-mode analysis of wee8_prebuilt targets.",
)

def setup_wee8_workspace_deps():
    """Creates workspace-mode stub repos needed to analyse wee8_prebuilt targets.

    In bzlmod mode these repos are provided by real module deps (abseil-cpp and
    icu resolve transitively via v8).  In workspace mode they are only present
    as analysis stubs so that //v8:wee8 can be analysed cleanly during a
    wildcard bazel test //... run.  The stubs are empty and cannot be used for
    actual compilation or linking; the wee8 smoke test is tagged manual and
    only exercised via the bzlmod CI leg where real implementations are present.
    """
    if "icu" not in native.existing_rules():
        _icu_workspace_stub(name = "icu")
    if "abseil-cpp" not in native.existing_rules():
        _abseil_cpp_workspace_stub(name = "abseil-cpp")
