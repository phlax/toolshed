
# TODO: these `//py/deps:reqs#*` entries are required because
# `[python-infer] imports = false` in pants.toml. They will be
# replaced by setup.cfg-driven auto-injection in the structural
# macro fix (follow-up PR). Once that lands, this `dependencies=`
# block should be removed entirely.
toolshed_library(
    "envoy.docs.sphinx_runner",
    dependencies=[
        "//py/deps:reqs#aio-run-runner",  # imported by library source
        "//py/deps:reqs#colorama",  # imported by library source
        "//py/deps:reqs#docutils",  # imported by library source
        "//py/deps:reqs#envoy-base-utils",  # imported by library source
        "//py/deps:reqs#packaging",  # imported by library source
        "//py/deps:reqs#protobuf",  # imported by library source
        "//py/deps:reqs#pygments",  # imported by library source
        "//py/deps:reqs#sphinx",  # imported by library source
        "//py/deps:reqs#sphinxcontrib-httpdomain",  # imported by library source
        "//py/deps:reqs#types-docutils",  # stubs for imported library source
        "//py/deps:reqs#types-pygments",  # stubs for imported library source
    ],
    sources=[
        "__init__.py",
        "cmd.py",
        "exceptions.py",
        "runner.py",
        "ext/*.py",
    ],
)
