"""Pytest conftest: provide stub ``pants.*`` modules when tests run outside
 a real Pants sandbox.

The synthetic-targets plugin under test imports from ``pants.engine.*`` at
module load time. To allow these tests to run with plain pytest (no Pants
RuleRunner), we install minimal stub modules into ``sys.modules`` before
any test module is collected. If a real ``pants`` distribution is already
importable (e.g. when Pants itself runs the tests), we leave the real
modules in place and do nothing.
"""

import sys
import types


def _install_pants_stubs() -> None:
    pants_module = types.ModuleType("pants")
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

    sys.modules["pants"] = pants_module
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
