
# TODO: these `//py/deps:reqs#*` entries are required because
# `[python-infer] imports = false` in pants.toml. They will be
# replaced by setup.cfg-driven auto-injection in the structural
# macro fix (follow-up PR). Once that lands, this `dependencies=`
# block should be removed entirely.
toolshed_library(
    "mypy-abstracts",
    dependencies=[
        "//py/deps:reqs#mypy",  # imported by library source
    ],
)
