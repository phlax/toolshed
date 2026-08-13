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

# Execution platform for the gcc toolchains.
#
# //toolchains/gcc:linux_x64_toolchain declares //compile:gcc_worker in its
# exec_compatible_with. @platforms//host does not carry that constraint, so with
# no other exec platform registered the gcc toolchain is rejected at the exec
# stage even when the target platform satisfies //compile:libstdcxx - and
# resolution falls through to LLVM.
platform(
    name = "linux_x86_64_gcc_worker",
    constraint_values = ["//compile:gcc_worker"],
    parents = ["@platforms//host"],
)
