load("@rules_cc//cc:extensions.bzl", "compatibility_proxy_repo")
load("@toolchains_llvm//toolchain:rules.bzl", "llvm_toolchain")
load("//:versions.bzl", "VERSIONS")

def setup_llvm_toolchain(llvm_version = None):
    compatibility_proxy_repo()
    llvm_toolchain(
        name = "llvm_toolchain",
        llvm_version = llvm_version or VERSIONS["llvm"],
        # Only declare cxx_cross_lib for genuine cross targets. The native
        # (host) arch must NOT be listed here: in the WORKSPACE path exec_pair
        # is resolved from host detection and may not string-match the
        # "linux-x86_64" key, so the `target_pair == exec_pair` guard in the
        # toolchains_llvm patch can fail to skip it. That flips the host
        # toolchain off its builtin-libc++ default and makes clang reject a
        # redundant `-stdlib=libc++` under -Wunused-command-line-argument.
        # bzlmod already applies cxx_cross_lib per-target, so this mirrors it.
        cxx_cross_lib = {
            "linux-aarch64": "@libcxx_libs_aarch64",
        },
        sysroot = {
            "linux-x86_64": "@sysroot_linux_amd64//:sysroot",
            "linux-aarch64": "@sysroot_linux_arm64//:sysroot",
        },
    )
