load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//dependency:reachability.bzl", "config_validation_error")

def _reachability_config_validation_test_impl(ctx):
    env = unittest.begin(ctx)

    message = config_validation_error(
        {"invalid": {"//dependency/test:reachability_mode": "extra"}},
        [],
    )
    asserts.equals(
        env,
        "Config 'invalid' varies '//dependency/test:reachability_mode' but it is not declared in flags. Declared flags: []",
        message,
    )

    message = config_validation_error(
        {"bare_key": {"wasm": "wasmtime"}},
        ["//dependency/test:reachability_mode"],
    )
    asserts.equals(
        env,
        (
            "Config 'bare_key' varies 'wasm', but config keys must be build setting labels starting with '//'. " +
            "Bazel does not support Starlark transitions on --define; use a build setting instead " +
            "(https://bazel.build/rules/config#user-defined-build-settings)."
        ),
        message,
    )

    return unittest.end(env)

reachability_config_validation_test = unittest.make(_reachability_config_validation_test_impl)
