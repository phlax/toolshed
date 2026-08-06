"""Rule to embed ICU data blob via objcopy resolved from the C++ toolchain."""

load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")

def _icudata_obj_impl(ctx):
    cc_toolchain = find_cpp_toolchain(ctx)
    src = ctx.file.src
    bin_file = ctx.actions.declare_file("icudt78_dat.bin")
    out = ctx.actions.declare_file("icudt78_dat.o")

    ctx.actions.run_shell(
        inputs = depset([src], transitive = [cc_toolchain.all_files]),
        outputs = [bin_file],
        command = "cp {} {}".format(src.path, bin_file.path),
    )

    ctx.actions.run_shell(
        inputs = depset([bin_file], transitive = [cc_toolchain.all_files]),
        outputs = [out],
        command = (
            "OBJCOPY=\"$(pwd)/{objcopy}\"; " +
            "cd {dir} && " +
            "\"$OBJCOPY\"" +
            " -I binary -O elf64-x86-64" +
            " --rename-section .data=.rodata,alloc,load,readonly,data,contents" +
            " --redefine-sym _binary_icudt78_dat_bin_start=icudt78_dat" +
            " icudt78_dat.bin icudt78_dat.o"
        ).format(
            dir = bin_file.dirname,
            objcopy = cc_toolchain.objcopy_executable,
        ),
    )

    return [DefaultInfo(files = depset([out]))]

icudata_obj = rule(
    implementation = _icudata_obj_impl,
    attrs = {
        "src": attr.label(allow_single_file = True),
        "_cc_toolchain": attr.label(
            default = Label("@bazel_tools//tools/cpp:current_cc_toolchain"),
        ),
    },
    fragments = ["cpp"],
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
)
