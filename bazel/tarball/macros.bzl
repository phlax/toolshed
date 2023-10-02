
def tarballs(
        name,
        prefix = "",
        unpack_script = "@envoy_toolshed//tarball:unpack.sh",
        pack_script = "@envoy_toolshed//tarball:pack.sh",
        zstd = None,
        visibility = ["//visibility:public"],
):
    if prefix:
        unpack_name = "%s_unpack" % prefix
        pack_name = "%s_pack" % prefix
        target_name = "%s_target" % prefix
        target_default_name = "%s_default" % prefix
    else:
        unpack_name = "unpack"
        pack_name = "pack"
        target_name = "target"
        target_default_name = "target_default"

    native.label_flag(
        name = target_name,
        build_setting_default = target_default_name,
        visibility = ["//visibility:public"],
    )

    native.genrule(
        name = "NULL",
        outs = ["NULL"],
        cmd = """
        echo NULL > $@
        """,
    )

    native.filegroup(
        name = target_default_name,
        srcs = [":NULL"],
    )

    env = {"TARGET": "$(location :%s)" % target_name}
    data = [":%s" % target_name]
    if zstd:
        data += [zstd]
        env["ZSTD"] = "$(location %s)" % zstd

    native.sh_binary(
        name = unpack_name,
        srcs = [unpack_script],
        visibility = visibility,
        data = data,
        env = env,
    )

    native.sh_binary(
        name = pack_name,
        srcs = [pack_script],
        visibility = visibility,
        data = data,
        env = env,
    )
