load(":wee8_package.bzl", "wee8_package")

licenses(["notice"])

config_setting(
    name = "linux_x86_64",
    constraint_values = [
        "@platforms//cpu:x86_64",
        "@platforms//os:linux",
    ],
)

config_setting(
    name = "linux_aarch64",
    constraint_values = [
        "@platforms//cpu:aarch64",
        "@platforms//os:linux",
    ],
)

alias(
    name = "wee8",
    actual = select({
        ":linux_x86_64": "@wee8_prebuilt_x86_64//:wee8",
        ":linux_aarch64": "@wee8_prebuilt_aarch64//:wee8",
        "//conditions:default": "@v8//:wee8",
    }),
    visibility = ["//visibility:public"],
)

cc_test(
    name = "wee8_smoke_test",
    srcs = ["wee8_smoke_test.cc"],
    copts = [
        "-DV8_ENABLE_WEBASSEMBLY=1",
        "-std=c++20",
    ],
    target_compatible_with = [
        "@platforms//cpu:x86_64",
        "@platforms//os:linux",
    ],
    deps = [":wee8"],
)

cc_binary(
    name = "wee8_smoke_link_aarch64",
    srcs = ["wee8_smoke_test.cc"],
    copts = [
        "-DV8_ENABLE_WEBASSEMBLY=1",
        "-std=c++20",
    ],
    target_compatible_with = [
        "@platforms//cpu:aarch64",
        "@platforms//os:linux",
    ],
    deps = [":wee8"],
)

# Per-arch packaging targets — tagged manual so they are not built by //...
# and are only triggered explicitly by the package-v8 CI job:
#   bazel build -c opt //v8:wee8_package_linux_x86_64   (ubuntu-24.04)
#   bazel build -c opt //v8:wee8_package_linux_aarch64  (ubuntu-24.04-arm)
[
    wee8_package(arch = arch)
    for arch in ["x86_64", "aarch64"]
]
