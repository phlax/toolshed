load("//bazel:nested.bzl", "load_envoy_nested_examples")

def _envoy_nested_examples_impl(ctx):
    load_envoy_nested_examples()

envoy_nested_examples = module_extension(
    implementation = _envoy_nested_examples_impl,
)
