"""Macros for dependency update utilities."""

load("@aspect_bazel_lib//lib:write_source_files.bzl", "write_source_files")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("//dependency:registry.bzl", "registry_bazelrc", "repo_registry")

def updater(
        name,
        dependencies,
        version_file,
        jq_toolchain = "@jq_toolchains//:resolved_toolchain",
        update_script = "@envoy_toolshed//dependency:bazel-update.sh",
        post_script = None,
        data = None,
        deps = None,
        dep_search = None,
        sha_search = None,
        version_search = None,
        repo_selector = None,
        sha_selector = None,
        url_selector = None,
        version_path_replace = None,
        version_selector = None,
        toolchains = None,
        pydict = False,
        **kwargs):
    """Create a shell-based dependency updater binary.

    Args:
      name: Target name.
      dependencies: Label for the dependency metadata input.
      version_file: Label for the version file to update.
      jq_toolchain: jq toolchain target label.
      update_script: Updater script label.
      post_script: Optional post-processing script label.
      data: Additional runtime data labels.
      deps: Additional runtime deps.
      dep_search: Optional dependency search override.
      sha_search: Optional sha search override.
      version_search: Optional version search override.
      repo_selector: Optional repo selector override.
      sha_selector: Optional sha selector override.
      url_selector: Optional URL selector override.
      version_path_replace: Optional version path replacement override.
      version_selector: Optional version selector override.
      toolchains: Additional toolchains.
      pydict: Whether to use Python dict matching defaults.
      **kwargs: Additional `sh_binary` keyword arguments.
    """
    toolchains = [jq_toolchain] + (toolchains or [])
    deps = deps or []
    data = (data or []) + [
        jq_toolchain,
        update_script,
        dependencies,
        version_file,
    ]
    args = [
        "$(location %s)" % version_file,
        "$(location %s)" % dependencies,
    ]
    env = {"JQ_BIN": "$(rootpath %s)" % jq_toolchain}
    if pydict:
        env["DEP_SEARCH"] = "__DEP__ = dict("
        env["SHA_SEARCH"] = "sha256 = \"__EXISTING_SHA__\","
        env["VERSION_SEARCH"] = "version = \"__EXISTING_VERSION__\","

    if dep_search:
        env["DEP_SEARCH"] = dep_search
    if sha_search:
        env["SHA_SEARCH"] = sha_search
    if version_search:
        env["VERSION_SEARCH"] = version_search
    if repo_selector:
        env["REPO_SELECTOR"] = repo_selector
    if sha_selector:
        env["SHA_SELECTOR"] = sha_selector
    if url_selector:
        env["URL_SELECTOR"] = url_selector
    if version_path_replace:
        env["VERSION_PATH_REPLACE"] = version_path_replace
    if version_selector:
        env["VERSION_SELECTOR"] = version_selector

    if post_script:
        data.append(post_script)
        env["VERSION_UPDATE_POST_SCRIPT"] = "$(location %s)" % post_script

    sh_binary(
        name = name,
        srcs = [update_script],
        data = data,
        env = env,
        args = args,
        deps = deps,
        toolchains = toolchains,
        **kwargs
    )

def registry_updater(
        name,
        bazelrc,
        repo = "https://github.com/envoyproxy/bazel-registry.git",
        url = "https://raw.githubusercontent.com/envoyproxy/bazel-registry",
        ref = "main",
        visibility = None,
        **kwargs):
    """Rewrite the `--registry=<url>/<sha>` pin in `bazelrc` to the current `ref` of `repo`.

    Creates `<name>` (a `write_source_files` runnable) plus private helpers
    `<name>_resolved` and `<name>_bazelrc`.

    Args:
      name: Target name for the generated updater.
      bazelrc: Label of the `.bazelrc` file to rewrite.
      repo: Git repository URL for the Bazel registry.
      url: Raw content URL prefix used in the pinned `--registry=` line.
      ref: Git branch to resolve in `repo`.
      visibility: Optional visibility for the runnable target.
      **kwargs: Additional `write_source_files` keyword arguments.
    """
    helper_tags = ["manual"] + kwargs.pop("tags", [])
    target_compatible_with = kwargs.pop("target_compatible_with", ["@platforms//os:linux"])
    repo_registry(
        name = name + "_resolved",
        ref = ref,
        repo = repo,
        tags = helper_tags,
        target_compatible_with = target_compatible_with,
        url = url,
    )
    registry_bazelrc(
        name = name + "_bazelrc",
        bazelrc = bazelrc,
        registry = ":" + name + "_resolved",
        tags = helper_tags,
        target_compatible_with = target_compatible_with,
        url = url,
    )
    if visibility != None:
        kwargs["visibility"] = visibility
    write_source_files(
        name = name,
        check_that_out_file_exists = False,
        diff_test = False,
        files = {bazelrc: ":" + name + "_bazelrc"},
        tags = helper_tags,
        target_compatible_with = target_compatible_with,
        **kwargs
    )
