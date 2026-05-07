import pytest

from toolshed_publish_reqs.names import _publish_req_target_name
from toolshed_publish_reqs.rules import _adaptors_for_install_requires


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
