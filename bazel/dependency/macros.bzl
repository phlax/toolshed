load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

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
        data += [post_script]
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

def _repo_path(label):
    parsed = Label(label)
    if parsed.workspace_name:
        fail("registry_updater only supports main-workspace files: {}".format(label))
    if parsed.package:
        return "{}/{}".format(parsed.package, parsed.name)
    return parsed.name

def registry_updater(
        name,
        bazelrc_files,
        module_files,
        registry_repo = "https://github.com/envoyproxy/bazel-registry",
        registry_branch = "main",
        registry_url_prefix = "https://raw.githubusercontent.com/envoyproxy/bazel-registry/",
        **kwargs):
    sh_binary(
        name = name,
        srcs = [Label("//dependency:registry.sh")],
        data = bazelrc_files + module_files + [
            Label("//dependency:registry.sh"),
            "@envoy_toolshed_jq//:modules",
            "@envoy_toolshed_jq//:modules_root.marker",
            "@jq_toolchains//:resolved_toolchain",
        ],
        deps = ["@bazel_tools//tools/bash/runfiles"],
        env = {
            "JQ_BIN": "$(rlocationpath @jq_toolchains//:resolved_toolchain)",
            "JQ_MODULES_ROOT_MARKER": "$(rlocationpath @envoy_toolshed_jq//:modules_root.marker)",
            "REGISTRY_BAZELRC_FILES": json.encode([_repo_path(label) for label in bazelrc_files]),
            "REGISTRY_BRANCH": registry_branch,
            "REGISTRY_MODULE_FILES": json.encode([_repo_path(label) for label in module_files]),
            "REGISTRY_REPO": registry_repo,
            "REGISTRY_URL_PREFIX": registry_url_prefix,
        },
        **kwargs
    )
