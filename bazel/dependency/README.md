# `//dependency`

## `registry_updater`

```starlark
load("@envoy_toolshed//dependency:macros.bzl", "registry_updater")

registry_updater(
    name = "registry",
    bazelrc_files = ["//:.bazelrc", "//api:.bazelrc"],
    module_files = ["//:MODULE.bazel", "//api:MODULE.bazel"],
)
```

Run the tool with:

```bash
bazel run @envoy_toolshed//dependency:registry -- [--hash SHA] [--set name=version]...
```

- `--hash` pins the target registry commit instead of resolving the configured branch head.
- `--set name=version` forces a hosted module to a specific version that exists at the target hash.
- `REGISTRY_CHANGES_OUTPUT` sets the workspace-relative report path (default: `registry-changes.json`).

The tool rewrites the configured `.bazelrc` hash and any changed version literals in the configured `MODULE.bazel` files, then writes:

```json
{
  "registry": {"old": "...", "new": "..."},
  "modules": [
    {"name": "...", "from": "...", "to": "...", "files": ["..."]}
  ]
}
```
