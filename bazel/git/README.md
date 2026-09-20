# Hermetic git prebuilt (`//git`)

Builds Linux `git-<version>-<platform>.tar.zst` release artifacts matching the
`bins-v*` packaging flow used for `sq`.

## Runtime layout

Each tarball contains:

- `BUILD.bazel`
- `bin/git`
- `libexec/git-core/git`
- `libexec/git-core/git-remote-http`
- `libexec/git-core/git-remote-https` (currently packaged as a byte-identical copy of `git-remote-http`)
- `share/git-core/ca-certificates.crt`
- `share/git-core/templates/**`

`bin/git` is self-contained: extract the tarball and run it directly.

## Runtime environment

The upstream BCR `git` overlay currently builds with `RUNTIME_PREFIX='false'`,
so the package ships a `/bin/sh` wrapper that sets:

- `GIT_EXEC_PATH=$here/libexec/git-core`
- `GIT_TEMPLATE_DIR=$here/share/git-core/templates`
- `GIT_SSL_CAINFO`, with precedence:
  1. explicit `GIT_SSL_CAINFO`
  2. `TOOLSHED_CA_BUNDLE`
  3. bundled `share/git-core/ca-certificates.crt`
- `SSL_CERT_FILE=$GIT_SSL_CAINFO`

## CA bundle maintenance

The bundled CA file is Mozilla's CA bundle published via curl.se and pinned in
`VERSIONS["cacert"]` in `/home/runner/work/toolshed/toolshed/bazel/versions.bzl`.
When bumping it:

1. Check the latest dated release on <https://curl.se/docs/caextract.html>.
2. Download `https://curl.se/ca/cacert-YYYY-MM-DD.pem`.
3. Compute its SHA-256.
4. Update `VERSIONS["cacert"]` and the matching `@cacert` `http_file` in
   `/home/runner/work/toolshed/toolshed/bazel/MODULE.bazel`.

> TODO: add macOS-ARM64 packaging when the bins pipeline grows beyond Linux
> parity with `sq`.
