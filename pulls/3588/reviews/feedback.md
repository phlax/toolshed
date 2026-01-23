The validated libs should have the standard names (`libcrypto.a`, `libssl.a`) since those are what consumers expect and what other code links against. The intermediate/unvalidated names should be the weird ones.

Currently the build outputs `libcrypto_validated.a` / `libssl_validated.a` - this will cause issues downstream (similar to issues we've had with `_internal.a` suffixes in Envoy's current build).

Suggested change:

```starlark
cmake(
    name = "_boringssl_build",
    out_static_libs = [
        "libcrypto_unvalidated.a",
        "libssl_unvalidated.a",
    ],
    ...
)

genrule(
    name = "_boringssl_validated",
    srcs = [":_boringssl_build"],
    outs = [
        "lib/libcrypto.a",
        "lib/libssl.a",
    ],
    cmd = """
        # validate...
        cp libcrypto_unvalidated.a $(location lib/libcrypto.a)
        cp libssl_unvalidated.a $(location lib/libssl.a)
    """,
)

cc_library(
    name = "crypto",
    srcs = ["lib/libcrypto.a"],
    ...
)

cc_library(
    name = "ssl",
    srcs = ["lib/libssl.a"],
    deps = [":crypto"],
    ...
) 
```

This way consumers get standard lib names, and only the private intermediate artifacts have the `_unvalidated` suffix.

Also note: the current `cc_library(srcs = [":_boringssl_validated"])` pulls in BOTH output files to both `ssl` and `crypto` targets - this should be split so each target only gets its own lib file to avoid duplicate symbol issues.