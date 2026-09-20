load("@bazel_skylib//rules:common_settings.bzl", "string_list_flag")
load("//dependency:macros.bzl", "registry_updater", "updater")

exports_files([
    "README.md",
    "bazel-update.sh",
    "macros.bzl",
    "reachability.bzl",
    "registry.bzl",
    "registry_bazelrc.sh",
])

# Private build settings used by reachability.bzl to transport exclusion lists
# through the configuration transition (including the exec-config transition).
# These are not part of the public API; use dependency_reachability's
# excluded_edges / excluded_patterns attributes instead.
string_list_flag(
    name = "_excluded_edges",
    build_setting_default = [],
    visibility = ["//visibility:public"],
)

string_list_flag(
    name = "_excluded_patterns",
    build_setting_default = [],
    visibility = ["//visibility:public"],
)

string_list_flag(
    name = "_attribution_patterns",
    build_setting_default = [],
    visibility = ["//visibility:public"],
)

updater(
    name = "update",
    dependencies = "//:dependency_versions",
    version_file = "//:versions.bzl",
)

registry_updater(
    name = "update_registry",
    bazelrc = "//:.bazelrc",
)
