"""Abstract dependency checker."""

import abc
import argparse
import asyncio
import json
import os
import pathlib
from functools import cached_property, wraps
from typing import Optional, Tuple, Type

import aiohttp

import abstracts

from aio.api import github
from aio.tasks import concurrent

from envoy.base import checker

from envoy.dependency.check import abstract, exceptions, typing


class ADependencyChecker(
        checker.AsyncChecker,
        metaclass=abstracts.Abstraction):
    """Dependency checker."""

    checks = ("cves", "dates", "issues", "releases")

    @property
    @abc.abstractmethod
    def access_token(self) -> Optional[str]:
        """Github access token."""
        if self.args.github_token:
            return pathlib.Path(self.args.github_token).read_text().strip()
        return os.getenv('GITHUB_TOKEN')

    @property
    def cve_config(self):
        return self.args.cve_config

    @cached_property
    def cves(self):
        return self.cves_class(
            self.dependencies,
            config_path=self.cve_config)

    @property  # type:ignore
    @abstracts.interfacemethod
    def cves_class(self) -> "abstract.ADependencyCVEs":
        """CVEs class."""
        raise NotImplementedError

    @cached_property
    def dep_ids(self) -> Tuple[str, ...]:
        """Tuple of dependency ids."""
        return tuple(dep.id for dep in self.dependencies)

    @property  # type:ignore
    @abstracts.interfacemethod
    def dependency_class(self) -> Type["abstract.ADependency"]:
        """Dependency class."""
        raise NotImplementedError

    @property
    @abc.abstractmethod
    def dependency_metadata(self) -> typing.DependenciesDict:
        """Dependency metadata (derived in Envoy's case from
        `repository_locations.bzl`)."""
        return json.loads(self.repository_locations_path.read_text())

    @cached_property
    def dependencies(self) -> Tuple["abstract.ADependency", ...]:
        """Tuple of dependencies."""
        deps = []
        for k, v in self.dependency_metadata.items():
            deps.append(self.dependency_class(k, v, self.github))
        return tuple(sorted(deps))

    @cached_property
    def disabled_checks(self):
        disabled = {}
        if not self.access_token:
            disabled["dates"] = "No github token supplied"
            disabled["issues"] = "No github token supplied"
            disabled["releases"] = "No github token supplied"
        return disabled

    @cached_property
    def github(self) -> github.GithubAPI:
        """Github API."""
        return github.GithubAPI(
            self.session, "",
            oauth_token=self.access_token)

    @cached_property
    def github_dependencies(self) -> Tuple["abstract.ADependency", ...]:
        """Tuple of dependencies."""
        deps = []
        for dep in self.dependencies:
            if not dep.github_url:
                urls = "\n".join(dep.urls)
                self.log.info(f"{dep.id} is not a GitHub repository\n{urls}")
                continue
            deps.append(dep)
        return tuple(deps)

    @cached_property
    def issues(self) -> "abstract.AGithubDependencyIssues":
        """Dependency issues."""
        return self.issues_class(self.github)

    @property  # type:ignore
    @abstracts.interfacemethod
    def issues_class(self) -> Type["abstract.AGithubDependencyIssues"]:
        """Dependency issues class."""
        raise NotImplementedError

    @property
    def repository_locations_path(self) -> pathlib.Path:
        return pathlib.Path(self.args.repository_locations)

    @cached_property
    def session(self) -> aiohttp.ClientSession:
        """HTTP client session."""
        return aiohttp.ClientSession()

    @property
    def sync_issues(self) -> bool:
        """Flag to determine whether to sync issues, or just warn."""
        return self.args.sync_issues

    def add_arguments(self, parser: argparse.ArgumentParser) -> None:
        super().add_arguments(parser)
        parser.add_argument('--github_token')
        parser.add_argument('--repository_locations')
        parser.add_argument('--cve_config')
        parser.add_argument('--sync_issues', action="store_true")

    async def check_cves(self) -> None:
        """Scan for CVEs in a parsed NIST CVE database."""
        for dep in self.dependencies:
            await self.dep_cve_check(dep)

    async def check_dates(self) -> None:
        """Check recorded dates match for dependencies."""
        for dep in self.github_dependencies:
            await self.dep_date_check(dep)

    async def check_issues(self) -> None:
        """Check dependency issues."""
        await self.issues_labels_check()
        for dep in self.github_dependencies:
            await self.dep_issue_check(dep)
        await self.issues_missing_dep_check()
        await self.issues_duplicate_check()

    async def check_releases(self) -> None:
        """Check dependencies for new releases."""
        for dep in self.github_dependencies:
            await self.dep_release_check(dep)

    async def dep_cve_check(
            self,
            dep: "abstract.ADependency") -> None:
        if not dep.cpe:
            self.log.info(f"No CPE listed for: {dep.id}")
            return
        warnings = []
        cve_data = await self.cves.data
        for failing_cve in sorted(dep.cve_check(self.cves.cpe_class, *cve_data)):
            warnings.append(
                f'{cve_data[0][failing_cve].format_failure(dep)}')
        if warnings:
            self.warn("cves", warnings)
        else:
            self.succeed("cves", [f"No CVEs found for: {dep.id}"])

    async def dep_date_check(
            self,
            dep: "abstract.ADependency") -> None:
        """Check dates for dependency."""
        if not await dep.release.date:
            self.error(
                "dates",
                [f"{dep.id} is a GitHub repository with no no inferrable "
                 "release date"])
        elif await dep.release_date_mismatch:
            self.error(
                "dates",
                [f"Date mismatch: {dep.id} "
                 f"{dep.release_date} != {await dep.release.date}"])
        else:
            self.succeed(
                "dates",
                [f"Date matches ({dep.release_date}): {dep.id}"])

    async def dep_issue_check(
            self,
            dep: "abstract.ADependency") -> None:
        """Check issues for dependency."""
        issue = (await self.issues.dep_issues).get(dep.id)
        newer_release = await dep.newer_release
        if not newer_release:
            if issue:
                # There is an open issue, but the dep is already
                # up-to-date.
                self.warn(
                    "issues",
                    [f"Stale issue: {dep.id} #{issue.number}"])
                if self.sync_issues:
                    await self._dep_issue_close_stale(issue, dep)
            else:
                # No issue required
                self.succeed(
                    "issues",
                    [f"No issue required: {dep.id}"])
            return
        if issue:
            if issue.version == (await dep.newer_release).version:
                # Required issue exists
                self.succeed(
                    "issues",
                    [f"Issue exists (#{issue.number}): {dep.id}"])
                return
            # Existing issue is showing incorrect version
            self.warn(
                "issues",
                [f"Out-of-date issue (#{issue.number}): {dep.id} "
                 f"({issue.version} -> {newer_release.version})"])
        else:
            # Issue is required to be added
            self.warn(
                "issues",
                [f"Missing issue: {dep.id} ({newer_release.version})"])
        if self.sync_issues:
            await self._dep_issue_create(issue, dep)

    async def dep_release_check(
            self,
            dep: "abstract.ADependency") -> None:
        """Check releases for dependency."""
        newer_release = await dep.newer_release
        if newer_release:
            self.warn(
                "releases",
                [f"Newer release ({newer_release.tag_name}): {dep.id}\n"
                 f"{dep.release_date} "
                 f"{dep.github_version_name}\n"
                 f"{await newer_release.date} "
                 f"{newer_release.tag_name} "])
        elif await dep.has_recent_commits:
            self.warn(
                "releases",
                [f"Recent commits ({await dep.recent_commits}): {dep.id}\n"
                 f"There have been {await dep.recent_commits} commits since "
                 f"{dep.github_version_name} landed on "
                 f"{dep.release_date}"])
        else:
            self.succeed(
                "releases",
                [f"Up-to-date ({dep.github_version_name}): {dep.id}"])

    async def issues_duplicate_check(self) -> None:
        """Check for duplicate issues for dependencies."""
        duplicates = False
        async for issue in self.issues.duplicate_issues:
            duplicates = True
            self.warn(
                "issues",
                [f"Duplicate issue for dependency (#{issue.number}): "
                 f"{issue.dep}"])
            if self.sync_issues:
                await self._issue_close_duplicate(issue)
        if not duplicates:
            self.succeed(
                "issues",
                ["No duplicate issues found."])

    async def issues_labels_check(self) -> None:
        """Check expected labels are present."""
        missing = False
        for label in await self.issues.missing_labels:
            missing = True
            # TODO: make this a warning if `sync_issues` and fix
            self.error(
                "issues",
                [f"Missing label: {label}"])
        if not missing:
            self.succeed(
                "issues",
                [f"All ({len(self.issues.labels)}) "
                 "required labels are available."])

    async def issues_missing_dep_check(self) -> None:
        """Check for missing dependencies for issues."""
        closed = False
        issues = await self.issues.open_issues
        for issue in issues:
            if issue.dep not in self.dep_ids:
                closed = True
                self.warn(
                    "issues",
                    [f"Missing dependency (#{issue.number}): {issue.dep}"])
                if self.sync_issues:
                    await self._issue_close_missing_dep(issue)
        if not closed:
            self.succeed(
                "issues",
                [f"All ({len(issues)}) issues have current dependencies."])

    async def on_checks_complete(self) -> int:
        await self.session.close()
        return await super().on_checks_complete()

    @checker.preload(when=["cves"])
    async def preload_cves(self) -> None:
        try:
            await self.cves.data
        except exceptions.CVECheckError as e:
            self.error("cves", ["Failed to load CVE data: {e}"])
            self.removed_checks.append("cves")

    @checker.preload(when=["dates"], unless=["releases", "issues"])
    async def preload_dates(self) -> None:
        for dep in self.github_dependencies:
            await dep.release.date

    @checker.preload(when=["issues"])
    async def preload_issues(self) -> None:
        await self.issues.missing_labels
        await self.issues.dep_issues

    @checker.preload(when=["releases", "issues"], blocks=["dates"])
    async def preload_releases(self) -> None:
        for dep in self.github_dependencies:
            newer = await dep.newer_release
            if not newer:
                await dep.recent_commits

    async def _dep_issue_close_stale(
            self,
            issue: "abstract.AGithubDependencyIssue",
            dep: "abstract.ADependency") -> None:
        await issue.close()
        self.log.notice(
            f"Closed stale issue (#{issue.number}): {dep.id}\n"
            f"{issue.title}\n{issue.body}")

    async def _dep_issue_create(
            self,
            issue: "abstract.AGithubDependencyIssue",
            dep: "abstract.ADependency") -> None:
        if await self.issues.missing_labels:
            self.error(
                "issues",
                [f"Unable to create issue for {dep.id}: missing labels"])
            return
        new_issue = await self.issues.create(dep)
        self.log.notice(
            f"Created issue (#{new_issue.number}): "
            f"{dep.id} {new_issue.version}\n"
            f"{new_issue.title}\n{new_issue.body}")
        if not issue:
            return
        await new_issue.close_old(issue, dep)
        self.log.notice(
            f"Closed old issue (#{issue.number}): "
            f"{dep.id} {issue.version}\n"
            f"{issue.title}\n{issue.body}")

    async def _issue_close_duplicate(
            self,
            issue: "abstract.AGithubDependencyIssue") -> None:
        current_issue = (await self.issues.dep_issues)[issue.dep]
        await current_issue.close_duplicate(issue)
        self.log.notice(
            f"Closed duplicate issue (#{issue.number}): {issue.dep}\n"
            f" {issue.title}\n"
            f"current issue #({current_issue.number}):\n"
            f" {current_issue.title}")

    async def _issue_close_missing_dep(
            self,
            issue: "abstract.AGithubDependencyIssue") -> None:
        """Close an issue that has no current dependency."""
        await issue.close()
        self.log.notice(
            f"Closed issue with no current dependency (#{issue.number})")
