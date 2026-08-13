package(default_visibility = ["//visibility:public"])

platform(
    name = "linux_x86_64_libstdcxx",
    constraint_values = ["//compile:libstdcxx"],
    parents = ["@toolchains_llvm//platforms:linux-x86_64"],
)

platform(
    name = "linux_aarch64_libstdcxx",
    constraint_values = ["//compile:libstdcxx"],
    parents = ["@toolchains_llvm//platforms:linux-aarch64"],
)

# Execution platform for local (non-RBE) gcc toolchain builds.
#
# //toolchains/gcc:*_toolchain requires //compile:gcc_worker in exec_compatible_with.
# @platforms//host does not carry that constraint, so without this exec platform
# the gcc toolchain is rejected at the exec stage and resolution falls through to
# LLVM. This platform is registered via --config=gcc for local builds; --config=rbe-gcc
# overrides it with the //platforms/rbe gcc platforms, which also carry the
# container-image exec property required by EngFlow RBE.
platform(
    name = "linux_x86_64_gcc_worker",
    constraint_values = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
        "//compile:gcc_worker",
    ],
    parents = ["@platforms//host"],
)
