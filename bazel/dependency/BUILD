load("//dependency:macros.bzl", "updater")
load("//dependency:registry.bzl", "repo_registry", "registry_bazelrc")
load("@aspect_bazel_lib//lib:write_source_files.bzl", "write_source_files")
load("@bazel_skylib//rules:common_settings.bzl", "string_flag")
load("@bazel_skylib//rules:common_settings.bzl", "string_list_flag")

exports_files([
    "bazel-update.sh",
    "macros.bzl",
    "reachability.bzl",
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

string_flag(
    name = "registry_repo",
    build_setting_default = "https://github.com/envoyproxy/bazel-registry.git",
    visibility = ["//visibility:public"],
)

string_flag(
    name = "registry_url",
    build_setting_default = "https://raw.githubusercontent.com/envoyproxy/bazel-registry",
    visibility = ["//visibility:public"],
)

repo_registry(
    name = "repo_registry",
    repo = ":registry_repo",
    url = ":registry_url",
)

registry_bazelrc(
    name = "updated_bazelrc",
    bazelrc = "//:.bazelrc",
    registry = ":repo_registry",
    url = ":registry_url",
)

write_source_files(
    name = "update_registry",
    files = {"//:.bazelrc": ":updated_bazelrc"},
    check_that_out_file_exists = False,
    diff_test = False,
)
