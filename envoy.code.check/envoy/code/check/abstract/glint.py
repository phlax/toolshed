
import asyncio
import pathlib
import os
import re
from functools import cached_property, partial
from typing import (
    Callable, Dict, Iterator, List,
    Pattern, Set, Tuple, Union)

import abstracts

from aio.core.dev import debug
from aio.core.functional import async_property, directory_context

from envoy.base import utils
from envoy.code.check import abstract


NOGLINT_RE = (
    r"[\w/]*\.patch$",
    r"^test/[\w/]*_corpus/[\w/]*",
    r"^tools/[\w/]*_corpus/[\w/]*",
    r"[\w/]*password_protected_password.txt$")


@debug.logging(
    log=__name__,
    show_cpu=True)
def _have_newlines(path, paths):
    with directory_context(path):
        return set(
            (target,
             (utils.last_n_bytes_of(target)
              == b'\n'))
            for target in paths)


class AGlintCheck(abstract.ACodeCheck, metaclass=abstracts.Abstraction):

    @classmethod
    def have_newlines(cls, path, *paths: str) -> Set[Tuple[str, bool]]:
        return _have_newlines(path, paths)

    @classmethod
    def filter_files(
            cls, files: Set[str],
            match: Callable) -> Set[str]:
        return set(
            path
            for path
            in files
            if not match(path))

    @async_property
    async def checker_files(self) -> Set[str]:
        return self.filter_files(
            await self.directory.files,
            self.noglint_re.match)

    @async_property
    async def files_with_mixed_tabs(self) -> Set[str]:
        files = await self.files_with_preceeding_tabs
        return (
            await self.directory.grep(
                ["-lP", r"^ "],
                target=files)
            if files
            else set())

    @async_property
    async def files_with_preceeding_tabs(self) -> Set[str]:
        files = await self.files
        if not files:
            return set()
        return await self.directory.grep(
            ["-lP", r"^\t"],
            target=await self.files)

    @async_property
    async def files_with_no_newline(self) -> Set[str]:
        return (
            await self.execute_in_batches(
                partial(self.have_newlines, self.directory.path),
                *await self.files)
            if await self.files
            else set())

    @async_property
    async def files_with_trailing_whitespace(self) -> Set[str]:
        files = await self.files
        if not files:
            return set()
        return await self.directory.grep(
            ["-lE", "[[:blank:]]$"],
            target=await self.files)

    @cached_property
    def noglint_re(self) -> Pattern[str]:
        return re.compile(r"|".join(NOGLINT_RE))

    @async_property(cache=True)
    async def problem_files(self) -> Dict[str, List[str]]:
        if not await self.files:
            return {}
        problems = await self.problems
        if not any(problems):
            return {}
        return self._check_problems(await self.files, problems)

    def _check_problems(
            self,
            files: Set[str],
            problems: Tuple[
                Set[str], Set[str], Set[str]]) -> Dict[str, List[str]]:
        problem_files: Dict[str, List[str]] = {}
        for path in files:
            file_problems = list(self._check_path(path, *problems))
            if file_problems:
                problem_files[path] = file_problems
        return problem_files

    @async_property
    async def problems(self) -> Tuple[Set[str], Set[str], Set[str]]:
        return await asyncio.gather(
            self.files_with_no_newline,
            self.files_with_mixed_tabs,
            self.files_with_trailing_whitespace)

    def _check_path(
            self,
            path: str,
            no_newline: Set[str],
            mixed_tabs: Set[str],
            trailing_whitespace: Set[str]) -> Iterator[str]:
        if path in no_newline:
            yield f"Missing final newline: {path}"
        if path in mixed_tabs:
            yield f"Mixed preceeding tabs and whitespace: {path}"
        if path in trailing_whitespace:
            yield f"Trailing whitespace: {path}"
