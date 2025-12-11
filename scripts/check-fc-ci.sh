#!/bin/bash
# Check CI status for all Firecracker versions
# Outputs: ci_passed=true|false to stdout (for GitHub Actions)

set -euo pipefail

VERSIONS_FILE="${1:-firecracker_versions.txt}"
FIRECRACKER_REPO_URL="https://github.com/e2b-dev/firecracker.git"
FIRECRACKER_REPO_API="e2b-dev/firecracker"

if [[ ! -f "$VERSIONS_FILE" ]]; then
  echo "Error: $VERSIONS_FILE not found" >&2
  exit 1
fi

# Clone FC repo to resolve commit hashes
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo "Cloning FC repo to resolve commit hashes..."
git clone --bare "$FIRECRACKER_REPO_URL" "$TEMP_DIR/fc-repo" 2>/dev/null
cd "$TEMP_DIR/fc-repo"

all_passed=true
failed_versions=""

# Read versions from file
while IFS= read -r version || [[ -n "$version" ]]; do
  # Skip comments and empty lines
  [[ "$version" =~ ^[[:space:]]*# ]] && continue
  [[ -z "$version" ]] && continue
  
  echo "Processing version: $version"
  
  # Resolve commit hash
  if [[ "$version" =~ ^([^_]+)_([0-9a-fA-F]+)$ ]]; then
    # Format: tag_shorthash
    tag="${BASH_REMATCH[1]}"
    shorthash="${BASH_REMATCH[2]}"
    commit_hash=$(git rev-parse --verify "$shorthash^{commit}" 2>/dev/null || echo "")
    version_name="${tag}_${shorthash}"
  else
    # Plain tag
    commit_hash=$(git rev-parse --verify "${version}^{commit}" 2>/dev/null || echo "")
    if [[ -n "$commit_hash" ]]; then
      short_hash=$(git rev-parse --short "$commit_hash")
      version_name="${version}_${short_hash}"
    else
      version_name="$version"
    fi
  fi
  
  if [[ -z "$commit_hash" ]]; then
    echo "  ⚠️ Could not resolve commit for $version"
    continue
  fi
  
  echo "  Checking CI for $version_name (commit: $commit_hash)..."
  
  # Check combined commit status
  status=$(gh api "/repos/${FIRECRACKER_REPO_API}/commits/${commit_hash}/status" --jq '.state' 2>/dev/null || echo "unknown")
  
  # Check check-runs (GitHub Actions)
  # Order matters: check pending BEFORE success (null conclusion means in-progress)
  check_conclusion=$(gh api "/repos/${FIRECRACKER_REPO_API}/commits/${commit_hash}/check-runs" --jq '
    if .total_count == 0 then "no_checks"
    elif ([.check_runs[].status] | any(. == "in_progress" or . == "queued")) then "pending"
    elif ([.check_runs[].conclusion] | any(. == "failure" or . == "cancelled" or . == "timed_out")) then "failure"
    elif ([.check_runs[].conclusion] | all(. == "success" or . == "skipped" or . == "neutral")) then "success"
    else "unknown"
    end
  ' 2>/dev/null || echo "unknown")
  
  echo "  Status: $status, Check runs: $check_conclusion"
  
  # Treat unknown as failure (API errors should block release)
  if [[ "$status" == "failure" ]] || [[ "$check_conclusion" == "failure" ]]; then
    echo "  ❌ CI failed for $version_name"
    all_passed=false
    failed_versions="${failed_versions}${version_name} "
  elif [[ "$status" == "pending" ]] || [[ "$check_conclusion" == "pending" ]]; then
    echo "  ⏳ CI still running for $version_name"
    all_passed=false
    failed_versions="${failed_versions}${version_name}(pending) "
  elif [[ "$status" == "unknown" ]] || [[ "$check_conclusion" == "unknown" ]]; then
    echo "  ⚠️ Could not verify CI status for $version_name (API error)"
    all_passed=false
    failed_versions="${failed_versions}${version_name}(unknown) "
  elif [[ "$status" == "success" ]] || [[ "$check_conclusion" == "success" ]]; then
    echo "  ✅ CI passed for $version_name"
  else
    # Catch-all for unexpected states
    echo "  ⚠️ Unexpected CI state for $version_name: status=$status, check_conclusion=$check_conclusion"
    all_passed=false
    failed_versions="${failed_versions}${version_name}(unexpected) "
  fi
done < "$OLDPWD/$VERSIONS_FILE"

echo ""
if [[ "$all_passed" == "true" ]]; then
  echo "All CI checks passed!"
  echo "ci_passed=true"
else
  echo "CI checks failed or pending for: $failed_versions"
  echo "ci_passed=false"
fi
