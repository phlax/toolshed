
envoy.code.check
================

Code checker used in Envoy proxy's CI.

This package provides an async checker that runs source-code checks against an
Envoy (or Envoy-like) checkout. Registered checks include:

- ``python_flake8`` and ``python_yapf`` for Python style
- ``yamllint`` for YAML files
- ``shellcheck`` for shell scripts
- ``glint`` for file hygiene checks
- ``gofmt`` for Go formatting
- ``runtime_guards`` consistency checks
- extension metadata, registration, owner, and fuzz-coverage checks
- changelog validation, including RST sanity checks

Usage
-----

Installed as a console script:

.. code-block:: console

   $ envoy.code.check --help

Run a subset of checks against a checkout:

.. code-block:: console

   $ envoy.code.check --check python_flake8 python_yapf --path /path/to/envoy

Run only against files changed since a given ref:

.. code-block:: console

   $ envoy.code.check --since main --path /path/to/envoy

See ``envoy.code.check --help`` for the full set of options.

Changelog entry areas
---------------------

Changelog area keys in ``changelogs/changelogs.yaml`` are filename-safe IDs and
use ``~`` to represent hierarchy (for example ``dns~cares``). Area titles are
the display form and use ``/`` (for example ``dns/cares``).

Changelog entries use the area key verbatim in
``changelogs/current/<section>/<area>__<slug>.rst`` (for example
``dns~cares__preserve-qid.rst``). The area portion of the filename must match
the YAML key directly; it is not decoded before lookup.

Area keys must match ``[a-z0-9_\\-~]+``. Area titles must match
``[a-z0-9_\\-/]+``.

Links
-----

- Source: https://github.com/envoyproxy/toolshed/tree/main/py/envoy.code.check
- Issues: https://github.com/envoyproxy/toolshed/issues
