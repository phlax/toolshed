#!/usr/bin/env bash

set -e -o pipefail


test_checkout () {
    if [[ ! -d ".git" ]]; then
        echo "fail:Repository not checked out (.git directory missing)" >> "$TEST_OUTPUT"
        return
    fi
    echo "success:Repository checked out successfully" >> "$TEST_OUTPUT"
}

test_depth () {
    local depth="${1}"
    local commit_count max_count parents
    # Only count first-parent history: on a PR merge ref the merge commit
    # has a second parent (the PR head) whose commits are also reachable,
    # which would inflate the count.
    commit_count=$(git rev-list --count --first-parent HEAD)
    echo "Commit count: $commit_count"
    # The shallow boundary is "within <depth> commits of the tip along any
    # path", so on a merge ref a base commit the PR side reaches within the
    # depth is fetched even when it is deeper on the first-parent side, and
    # the first-parent chain runs past <depth>: by up to depth-2 commits (the
    # PR head is at depth 2 and can at most reach depth-2 base commits).
    parents=$(git rev-list --parents -n 1 HEAD | wc -w)
    max_count="${depth}"
    if [[ "$parents" -gt 2 && "$depth" -gt 2 ]]; then
        max_count=$((depth * 2 - 2))
    fi
    if [[ "$commit_count" -lt "${depth}" || "$commit_count" -gt "${max_count}" ]]; then
        echo "fail:Expected fetch-depth ${depth} (${depth}..${max_count} commits), but got $commit_count commits" >> "$TEST_OUTPUT"
    else
        echo "success:fetch-depth ${depth} applied correctly, got $commit_count commits" >> "$TEST_OUTPUT"
        git log --oneline --first-parent
    fi
}

test_git_config () {
    # Verify git user.name is set
    expected_name="${1}"
    expected_email="${2}"
    GIT_NAME="$(git config --global user.name)"
    if [[ "$GIT_NAME" != "${expected_name}" ]]; then
        echo "fail:Expected git user.name '${expected_name}', got '$GIT_NAME'" >> "$TEST_OUTPUT"
    else
        echo "success:Git user.name correctly set: $GIT_NAME" >> "$TEST_OUTPUT"
    fi
    GIT_EMAIL=$(git config --global user.email)
    if [[ "$GIT_EMAIL" != "${expected_email}" ]]; then
        echo "fail:Expected git user.email '${expected_email}', got '$GIT_EMAIL'" >> "$TEST_OUTPUT"
    else
        echo "success:Git user.email correctly set: $GIT_EMAIL" >> "$TEST_OUTPUT"
    fi
}

test_repository () {
    # Verify we're in the right repository
    local expected_repo="${1}"
    current_repo=$(git config --get remote.origin.url | sed 's/.*github.com[:/]//' | sed 's/.git$//')
    if [[ "$current_repo" != "$expected_repo" ]]; then
        echo "fail:Wrong repository. Expected '$expected_repo', got '$current_repo'" >> "$TEST_OUTPUT"
        return
    fi
    echo "success:Correct repository: $current_repo" >> "$TEST_OUTPUT"
}

test_branch () {
    # Verify branch
    output_branch=${1}
    expected_branch=${2}
    if [[ -z "$output_branch" ]]; then
        echo "fail: branch-name output is empty" >> "$TEST_OUTPUT"
        return
    fi
    if [[ "$expected_branch" != "$output_branch" ]]; then
        echo "fail:Wrong branch. Expected '$expected_branch', got '$output_branch'" >> "$TEST_OUTPUT"
        return
    fi
    echo "success:branch-name output: $output_branch" >> "$TEST_OUTPUT"
}
