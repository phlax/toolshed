import sys
import types

import pytest


def _install_pants_stubs() -> None:
    pants = types.ModuleType("pants")
    engine = types.ModuleType("pants.engine")
    fs = types.ModuleType("pants.engine.fs")
    fs.PathGlobs = object
    internals = types.ModuleType("pants.engine.internals")
    synthetic_targets = types.ModuleType(
        "pants.engine.internals.synthetic_targets")

    class _SyntheticAddressMaps:
        @classmethod
        def for_targets_request(cls, *_args, **_kwargs):
            return cls()

    class _SyntheticTargetsRequest:
        SINGLE_REQUEST_FOR_ALL_TARGETS = ""

    synthetic_targets.SyntheticAddressMaps = _SyntheticAddressMaps
    synthetic_targets.SyntheticTargetsRequest = _SyntheticTargetsRequest
    target_adaptor = types.ModuleType("pants.engine.internals.target_adaptor")

    class _FakeTargetAdaptor:
        def __init__(self, type_alias, **kwargs):
            self.type_alias = type_alias
            self.kwargs = kwargs

    target_adaptor.TargetAdaptor = _FakeTargetAdaptor
    intrinsics = types.ModuleType("pants.engine.intrinsics")
    intrinsics.digest_to_snapshot = None
    intrinsics.get_digest_contents = None
    intrinsics.path_globs_to_digest = None
    rules = types.ModuleType("pants.engine.rules")
    rules.collect_rules = lambda: []
    rules.rule = lambda func: func
    unions = types.ModuleType("pants.engine.unions")
    unions.UnionRule = object

    sys.modules["pants"] = pants
    sys.modules["pants.engine"] = engine
    sys.modules["pants.engine.fs"] = fs
    sys.modules["pants.engine.internals"] = internals
    sys.modules["pants.engine.internals.synthetic_targets"] = synthetic_targets
    sys.modules["pants.engine.internals.target_adaptor"] = target_adaptor
    sys.modules["pants.engine.intrinsics"] = intrinsics
    sys.modules["pants.engine.rules"] = rules
    sys.modules["pants.engine.unions"] = unions


try:
    import pants  # noqa: F401
except ModuleNotFoundError:
    _install_pants_stubs()

from toolshed_publish_reqs.names import (  # noqa: E402
    _publish_req_target_name)
from toolshed_publish_reqs.rules import (  # noqa: E402
    _adaptors_for_install_requires)


@pytest.mark.parametrize(
    ("req_str", "expected"),
    (
        ("aiohttp>=3.8.1", "_publish__aiohttp"),
        ("PyYAML", "_publish__pyyaml"),
        ("pytest-asyncio", "_publish__pytest_asyncio"),
        ("Foo.Bar_Baz", "_publish__foo_bar_baz"),
        ("package[extra]>=1.0", "_publish__package"),
        ("package; python_version >= '3.10'", "_publish__package"),
        ("foo----bar", "_publish__foo_bar"),
        ("  aiohttp>=3.8.1  ", "_publish__aiohttp"),
    ),
)
def test_publish_req_target_name(req_str: str, expected: str):
    assert _publish_req_target_name(req_str) == expected


def test_adaptors_for_install_requires_basic():
    result = _adaptors_for_install_requires(
        "py/foo",
        ["aiohttp>=3.8.1", "PyYAML"])
    assert len(result) == 2
    assert result[0].type_alias == "python_requirement"
    assert result[0].kwargs["name"] == "_publish__aiohttp"
    assert result[0].kwargs["requirements"] == ["aiohttp>=3.8.1"]
    assert result[0].kwargs["resolve"] == "publish"
    assert result[0].kwargs["__description_of_origin__"] == "py/foo/setup.cfg"
    assert result[1].kwargs["name"] == "_publish__pyyaml"


def test_adaptors_for_install_requires_empty():
    result = _adaptors_for_install_requires("py/foo", [])
    assert result == ()


def test_adaptors_for_install_requires_invalid():
    with pytest.raises(ValueError) as exc_info:
        _adaptors_for_install_requires(
            "py/foo",
            ["@@not-a-valid-requirement@@"])
    assert "@@not-a-valid-requirement@@" in str(exc_info.value)
    assert "py/foo/setup.cfg" in str(exc_info.value)
