load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load("@bazel_skylib//rules:common_settings.bzl", "string_list_flag")
load("//dependency:macros.bzl", "module_deps_json", "module_updater", "registry_updater", "updater")

exports_files([
    "README.md",
    "bazel-update.sh",
    "macros.bzl",
    "module-update.sh",
    "module_deps_json.jq",
    "reachability.bzl",
    "registries.jq",
    "registry.bzl",
    "registry_bazelrc.sh",
    "report.jq",
    "resolve.jq",
    "version.jq",
])

filegroup(
    name = "jq_libs",
    srcs = [
        "module_deps_json.jq",
        "registries.jq",
        "report.jq",
        "resolve.jq",
        "version.jq",
    ],
    visibility = ["//visibility:public"],
)

bzl_library(
    name = "registry_bzl",
    srcs = ["registry.bzl"],
    visibility = ["//visibility:private"],
)

string_list_flag(name = "_excluded_edges", build_setting_default = [], visibility = ["//visibility:public"])
string_list_flag(name = "_excluded_patterns", build_setting_default = [], visibility = ["//visibility:public"])
string_list_flag(name = "_attribution_patterns", build_setting_default = [], visibility = ["//visibility:public"])

updater(name = "update", dependencies = "//:dependency_versions", version_file = "//:versions.bzl")
registry_updater(name = "update_registry", bazelrc = "//:.bazelrc")
module_deps_json(name = "toolshed_module_deps", lockfile = "//:MODULE.bazel.lock", visibility = ["//visibility:private"])
module_updater(name = "update_module", bazelrc = "//:.bazelrc", dependencies = ":toolshed_module_deps", module_file = "//:MODULE.bazel")
