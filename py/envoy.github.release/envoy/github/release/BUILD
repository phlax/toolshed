
# TODO: these `//py/deps:reqs#*` entries are required because
# `[python-infer] imports = false` in pants.toml. They will be
# replaced by setup.cfg-driven auto-injection in the structural
# macro fix (follow-up PR). Once that lands, this `dependencies=`
# block should be removed entirely.
toolshed_library(
    "envoy.github.release",
    dependencies=[
        "//py/deps:reqs#aiofiles",  # imported by library source
        "//py/deps:reqs#types-aiofiles",  # stubs for imported library source
    ],
    tags=["abstract-types"],
    sources=[
        "__init__.py",
        "assets.py",
        "manager.py",
        "release.py",
        "stream/__init__.py",
        "stream/base.py",
        "stream/_reader.py",
        "stream/_writer.py",
    ],
)
