#!/usr/bin/env python3
"""
Validation script for Firecracker release workflow.

This script validates inputs, resolves tags/commits, checks CI status,
and determines which architectures need to be built.
"""

import argparse
import json
import os
import subprocess
import sys
from dataclasses import dataclass
from typing import Optional


@dataclass
class ValidationResult:
    """Result of the validation process."""
    tag: str
    commit_hash: str
    version_name: str
    build_matrix: dict
    skip_build: bool
    error: Optional[str] = None


def run_command(cmd: list[str], check: bool = True) -> subprocess.CompletedProcess:
    """Run a command and return the result."""
    return subprocess.run(cmd, capture_output=True, text=True, check=check)


def gh_api(endpoint: str) -> Optional[dict]:
    """Call the GitHub API using the gh CLI."""
    result = run_command(["gh", "api", endpoint], check=False)
    if result.returncode != 0:
        return None
    return json.loads(result.stdout)


def validate_inputs(tag: Optional[str], commit_hash: Optional[str], build_amd64: bool, build_arm64: bool) -> Optional[str]:
    """Validate inputs."""
    if not build_amd64 and not build_arm64:
        return "At least one architecture must be selected"
    if not tag and not commit_hash:
        return "Either tag or commit_hash must be provided"
    return None


def resolve_tag_to_commit(tag: str, repo: str = "e2b-dev/firecracker") -> tuple[str, Optional[str]]:
    """
    Resolve a tag to its commit hash.

    Returns (commit_hash, error_message).
    """
    data = gh_api(f"repos/{repo}/git/ref/tags/{tag}")
    if not data:
        return "", f"Tag {tag} does not exist in {repo} repository"

    commit_hash = data["object"]["sha"]

    # Handle annotated tags (need to dereference to get commit SHA)
    tag_object = gh_api(f"repos/{repo}/git/tags/{commit_hash}")
    if tag_object and "object" in tag_object:
        commit_hash = tag_object["object"]["sha"]

    return commit_hash, None


def validate_commit(commit_hash: str, repo: str = "e2b-dev/firecracker") -> tuple[str, Optional[str]]:
    """
    Validate that a commit exists.

    Returns (full_sha, error_message).
    """
    data = gh_api(f"repos/{repo}/commits/{commit_hash}")
    if not data:
        return "", f"Commit {commit_hash} does not exist in {repo} repository"
    return data["sha"], None


def find_tag_for_commit(commit_hash: str, repo: str = "e2b-dev/firecracker") -> tuple[str, Optional[str]]:
    """
    Find the most recent tag that is an ancestor of (or equal to) the given commit.

    Returns (tag_name, error_message).
    """
    # List tags (GitHub returns them in reverse chronological order by default)
    tags_data = gh_api(f"repos/{repo}/tags?per_page=100")
    if not tags_data:
        return "", "Failed to fetch tags from repository"

    for tag_info in tags_data:
        tag_name = tag_info["name"]
        tag_commit = tag_info["commit"]["sha"]

        # Check if this tag's commit is the same as our target
        if tag_commit == commit_hash:
            return tag_name, None

        # Check if tag is an ancestor of our commit using compare API
        compare_data = gh_api(f"repos/{repo}/compare/{tag_commit}...{commit_hash}")
        if compare_data and compare_data.get("status") in ("ahead", "identical"):
            return tag_name, None

    return "", f"No tag found that is an ancestor of commit {commit_hash}"


def resolve_tag_and_commit(
    tag: Optional[str],
    input_hash: Optional[str],
    repo: str = "e2b-dev/firecracker"
) -> tuple[str, str, Optional[str]]:
    """
    Resolve tag and commit hash.

    Returns (tag, commit_hash, error_message).
    """
    if tag and input_hash:
        # Both provided: validate commit exists and is at or after the tag
        commit_hash, error = validate_commit(input_hash, repo)
        if error:
            return "", "", error

        # Resolve tag to its commit
        tag_commit, error = resolve_tag_to_commit(tag, repo)
        if error:
            return "", "", error

        # Verify commit is at or after the tag (in the same tree)
        if commit_hash != tag_commit:
            compare_data = gh_api(f"repos/{repo}/compare/{tag_commit}...{commit_hash}")
            if not compare_data:
                return "", "", f"Failed to compare tag {tag} with commit {input_hash}"

            status = compare_data.get("status")
            if status not in ("ahead", "identical"):
                return "", "", (
                    f"Commit {input_hash[:7]} is not at or after tag {tag}. "
                    f"The commit must be in the same tree and after the tag. "
                    f"(compare status: {status})"
                )

        return tag, commit_hash, None

    if tag:
        # Only tag provided: resolve to commit
        commit_hash, error = resolve_tag_to_commit(tag, repo)
        if error:
            return "", "", error
        return tag, commit_hash, None

    if input_hash:
        # Only commit provided: validate and find tag
        commit_hash, error = validate_commit(input_hash, repo)
        if error:
            return "", "", error

        resolved_tag, error = find_tag_for_commit(commit_hash, repo)
        if error:
            return "", "", error
        return resolved_tag, commit_hash, None

    return "", "", "Either tag or commit_hash must be provided"


def check_ci_status(commit_hash: str, repo: str = "e2b-dev/firecracker") -> tuple[bool, str]:
    """
    Check CI status for a commit.

    Returns (success, message).
    """
    # Check commit status API
    status_response = gh_api(f"/repos/{repo}/commits/{commit_hash}/status")
    if not status_response:
        status_response = {"state": "unknown", "total_count": 0}

    status = status_response.get("state", "unknown")
    status_count = status_response.get("total_count", 0)

    # Check check-runs API
    check_response = gh_api(f"/repos/{repo}/commits/{commit_hash}/check-runs")
    if not check_response:
        check_response = {"total_count": 0, "check_runs": []}

    check_count = check_response.get("total_count", 0)
    check_runs = check_response.get("check_runs", [])

    # Determine check conclusion
    if check_count == 0:
        check_conclusion = "no_checks"
    elif any(cr.get("status") in ("in_progress", "queued") for cr in check_runs):
        check_conclusion = "pending"
    elif any(cr.get("conclusion") in ("failure", "cancelled", "timed_out") for cr in check_runs):
        check_conclusion = "failure"
    elif all(cr.get("conclusion") in ("success", "skipped", "neutral") for cr in check_runs):
        check_conclusion = "success"
    else:
        check_conclusion = "unknown"

    print(f"Status API: state={status}, count={status_count}", file=sys.stderr)
    print(f"Check-runs API: conclusion={check_conclusion}, count={check_count}", file=sys.stderr)

    if status == "failure" or check_conclusion == "failure":
        return False, f"CI failed for commit {commit_hash} - refusing to build"

    if check_conclusion == "pending" or (status == "pending" and status_count > 0):
        return False, f"CI is still running for commit {commit_hash} - refusing to build"

    if status == "success" or check_conclusion == "success":
        return True, f"CI passed for commit {commit_hash}"

    if status_count == 0 and check_count == 0:
        print(f"::warning::No CI checks found for commit {commit_hash} - proceeding anyway", file=sys.stderr)
        return True, f"No CI checks found for commit {commit_hash} - proceeding anyway"

    print(f"::warning::Could not definitively verify CI status - proceeding anyway", file=sys.stderr)
    return True, f"Could not definitively verify CI status (status={status}, check_conclusion={check_conclusion}) - proceeding anyway"


def check_gcs_artifact(bucket: str, version_name: str, arch: str) -> bool:
    """Check if an artifact exists in GCS."""
    gcs_path = f"gs://{bucket}/firecrackers/{version_name}/{arch}/firecracker"
    result = run_command(["gcloud", "storage", "ls", gcs_path], check=False)
    return result.returncode == 0


def check_release_artifacts(github_repo: str, version_name: str) -> set[str]:
    """Get the set of artifact names in a GitHub release."""
    result = run_command([
        "gh", "release", "view", version_name,
        "--repo", github_repo,
        "--json", "assets",
        "-q", ".assets[].name"
    ], check=False)

    if result.returncode != 0:
        return set()

    return set(result.stdout.strip().split("\n")) if result.stdout.strip() else set()


def check_existing_artifacts(
    version_name: str,
    build_amd64: bool,
    build_arm64: bool,
    gcp_bucket: str,
    github_repo: str
) -> tuple[dict, bool]:
    """
    Check existing artifacts and generate build matrix.

    Returns (build_matrix, skip_build).
    """
    need_amd64 = False
    need_arm64 = False

    release_assets = check_release_artifacts(github_repo, version_name)

    for arch, requested in [("amd64", build_amd64), ("arm64", build_arm64)]:
        if not requested:
            continue

        gcs_exists = check_gcs_artifact(gcp_bucket, version_name, arch)
        release_exists = f"firecracker-{arch}" in release_assets

        print(f"GCS: {arch} artifact {'exists' if gcs_exists else 'missing'}", file=sys.stderr)
        print(f"Release: {arch} artifact {'exists' if release_exists else 'missing'}", file=sys.stderr)

        if not gcs_exists or not release_exists:
            if arch == "amd64":
                need_amd64 = True
            else:
                need_arm64 = True

    if not need_amd64 and not need_arm64:
        print("", file=sys.stderr)
        print("==============================================", file=sys.stderr)
        print("SKIPPING BUILD: All requested artifacts already exist", file=sys.stderr)
        print("==============================================", file=sys.stderr)
        print("", file=sys.stderr)
        print(f"::notice::Skipped build - all requested artifacts already exist in both GCS and GitHub release", file=sys.stderr)
        return {"include": []}, True

    # Generate build matrix
    include = []
    if need_amd64:
        include.append({"arch": "amd64", "runner": "ubuntu-24.04"})
    if need_arm64:
        include.append({"arch": "arm64", "runner": "ubuntu-24.04-arm"})

    return {"include": include}, False


def write_github_output(outputs: dict[str, str]) -> None:
    """Write outputs to GITHUB_OUTPUT file."""
    output_file = os.environ.get("GITHUB_OUTPUT")
    if output_file:
        with open(output_file, "a") as f:
            for key, value in outputs.items():
                f.write(f"{key}={value}\n")
    else:
        # For local testing, print to stdout
        for key, value in outputs.items():
            print(f"{key}={value}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate Firecracker release inputs")
    parser.add_argument("--tag", default="", help="Firecracker version tag (e.g., v1.14.1)")
    parser.add_argument("--commit-hash", default="", help="Full commit hash to build")
    parser.add_argument("--build-amd64", type=lambda x: x.lower() == "true", default=True,
                        help="Build for amd64 architecture")
    parser.add_argument("--build-arm64", type=lambda x: x.lower() == "true", default=True,
                        help="Build for arm64 architecture")
    parser.add_argument("--gcp-bucket", default=os.environ.get("GCP_BUCKET_NAME", ""),
                        help="GCP bucket name")
    parser.add_argument("--github-repo", default=os.environ.get("GITHUB_REPOSITORY", ""),
                        help="GitHub repository (owner/repo)")

    args = parser.parse_args()

    tag = args.tag if args.tag else None
    commit_hash_input = args.commit_hash if args.commit_hash else None

    # Step 1: Validate inputs
    error = validate_inputs(tag, commit_hash_input, args.build_amd64, args.build_arm64)
    if error:
        print(f"::error::{error}", file=sys.stderr)
        return 1

    # Step 2: Resolve tag and commit hash
    if tag:
        print(f"Resolving tag {tag}...", file=sys.stderr)
    else:
        print(f"Finding tag for commit {commit_hash_input}...", file=sys.stderr)

    tag, commit_hash, error = resolve_tag_and_commit(tag, commit_hash_input)
    if error:
        print(f"::error::{error}", file=sys.stderr)
        return 1

    short_hash = commit_hash[:7]
    version_name = f"{tag}_{short_hash}"

    print(f"Tag: {tag}", file=sys.stderr)
    print(f"Full commit hash: {commit_hash}", file=sys.stderr)
    print(f"Short hash: {short_hash}", file=sys.stderr)
    print(f"Version name: {version_name}", file=sys.stderr)

    # Step 3: Check CI status
    print(f"Checking CI status for commit {commit_hash}...", file=sys.stderr)
    ci_ok, ci_message = check_ci_status(commit_hash)
    if not ci_ok:
        print(f"::error::{ci_message}", file=sys.stderr)
        return 1
    print(ci_message, file=sys.stderr)

    # Step 4: Check existing artifacts and generate build matrix
    build_matrix, skip_build = check_existing_artifacts(
        version_name,
        args.build_amd64,
        args.build_arm64,
        args.gcp_bucket,
        args.github_repo
    )

    print(f"Build matrix: {json.dumps(build_matrix)}", file=sys.stderr)

    # Write outputs
    write_github_output({
        "commit_hash": commit_hash,
        "version_name": version_name,
        "build_matrix": json.dumps(build_matrix),
        "skip_build": "true" if skip_build else "false"
    })

    return 0


if __name__ == "__main__":
    sys.exit(main())
