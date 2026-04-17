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


def validate_inputs(build_amd64: bool, build_arm64: bool) -> Optional[str]:
    """Validate that at least one architecture is selected."""
    if not build_amd64 and not build_arm64:
        return "At least one architecture must be selected"
    return None


def resolve_tag_and_commit(
    tag: str,
    input_hash: Optional[str],
    repo: str = "e2b-dev/firecracker"
) -> tuple[str, Optional[str]]:
    """
    Resolve the commit hash for a tag.

    Returns (commit_hash, error_message).
    """
    if input_hash:
        # Commit hash provided: validate it exists
        data = gh_api(f"repos/{repo}/commits/{input_hash}")
        if not data:
            return "", f"Commit {input_hash} does not exist in {repo} repository"
        return data["sha"], None

    # No commit hash: look up from tag
    data = gh_api(f"repos/{repo}/git/ref/tags/{tag}")
    if not data:
        return "", f"Tag {tag} does not exist in {repo} repository"

    commit_hash = data["object"]["sha"]

    # Handle annotated tags (need to dereference to get commit SHA)
    tag_object = gh_api(f"repos/{repo}/git/tags/{commit_hash}")
    if tag_object and "object" in tag_object:
        commit_hash = tag_object["object"]["sha"]

    return commit_hash, None


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
    parser.add_argument("--tag", required=True, help="Firecracker version tag (e.g., v1.14.1)")
    parser.add_argument("--commit-hash", default="", help="Full commit hash to build (optional)")
    parser.add_argument("--build-amd64", type=lambda x: x.lower() == "true", default=True,
                        help="Build for amd64 architecture")
    parser.add_argument("--build-arm64", type=lambda x: x.lower() == "true", default=True,
                        help="Build for arm64 architecture")
    parser.add_argument("--gcp-bucket", default=os.environ.get("GCP_BUCKET_NAME", ""),
                        help="GCP bucket name")
    parser.add_argument("--github-repo", default=os.environ.get("GITHUB_REPOSITORY", ""),
                        help="GitHub repository (owner/repo)")

    args = parser.parse_args()

    # Step 1: Validate inputs
    error = validate_inputs(args.build_amd64, args.build_arm64)
    if error:
        print(f"::error::{error}", file=sys.stderr)
        return 1

    # Step 2: Resolve tag and commit hash
    print(f"Resolving tag {args.tag}...", file=sys.stderr)
    commit_hash, error = resolve_tag_and_commit(
        args.tag,
        args.commit_hash if args.commit_hash else None
    )
    if error:
        print(f"::error::{error}", file=sys.stderr)
        return 1

    short_hash = commit_hash[:7]
    version_name = f"{args.tag}_{short_hash}"

    print(f"Tag: {args.tag}", file=sys.stderr)
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
        "tag": args.tag,
        "commit_hash": commit_hash,
        "version_name": version_name,
        "build_matrix": json.dumps(build_matrix),
        "skip_build": "true" if skip_build else "false"
    })

    return 0


if __name__ == "__main__":
    sys.exit(main())
