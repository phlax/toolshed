load(":hunspell_test.bzl", "hunspell_toolchain_test")

# Resolves `//hunspell:toolchain_type` (the source toolchain in toolshed, a prebuilt one
# once published) and checks the ispell pipe protocol with an empty environment.
hunspell_toolchain_test(
    name = "hunspell_toolchain_test",
    check = "assert_hunspell_pipe.sh",
    target_compatible_with = ["@platforms//os:linux"],
)
