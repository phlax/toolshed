# Registry pin updater

`registry_updater` rewrites a `.bazelrc` `--registry=<url>/<sha>` pin to the
current commit for a branch in a git-backed Bazel registry.

```starlark
load("@envoy_toolshed//dependency:macros.bzl", "registry_updater")

registry_updater(
    name = "update_registry",
    bazelrc = "//:.bazelrc",
)
```

Signature:

```starlark
registry_updater(
    name,
    bazelrc,
    repo = "https://github.com/envoyproxy/bazel-registry.git",
    url = "https://raw.githubusercontent.com/envoyproxy/bazel-registry",
    ref = "main",
    visibility = None,
    **kwargs
)
```

The updater creates a `write_source_files` runnable plus private helper targets
to resolve the current registry commit and rewrite the selected `.bazelrc`.
Those helper actions are tagged `manual` so `//...` does not trigger the
networked resolution step. The generated helper targets are Linux-only, matching
the currently supported hermetic git toolchain platforms.

The registry resolution action is marked `local`, `no-cache`, `no-remote`, and
`requires-network`, and it uses the hermetic `//git:toolchain_type` git
toolchain rather than host git.
