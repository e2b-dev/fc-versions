#!/bin/bash

set -euo pipefail

FIRECRACKER_REPO_API="e2b-dev/firecracker"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <versions_json>" >&2
  exit 1
fi

versions_json="$1"

all_passed=true
failed_versions=""

while IFS='|' read -r version commit_hash version_name; do
  status_response=$(gh api "/repos/${FIRECRACKER_REPO_API}/commits/${commit_hash}/status" 2>/dev/null || echo '{"state":"unknown","total_count":0}')
  status=$(echo "$status_response" | jq -r '.state')
  status_count=$(echo "$status_response" | jq -r '.total_count')
  
  check_response=$(gh api "/repos/${FIRECRACKER_REPO_API}/commits/${commit_hash}/check-runs" 2>/dev/null || echo '{"total_count":0}')
  check_count=$(echo "$check_response" | jq -r '.total_count')
  check_conclusion=$(echo "$check_response" | jq -r '
    if .total_count == 0 then "no_checks"
    elif ([.check_runs[].status] | any(. == "in_progress" or . == "queued")) then "pending"
    elif ([.check_runs[].conclusion] | any(. == "failure" or . == "cancelled" or . == "timed_out")) then "failure"
    elif ([.check_runs[].conclusion] | all(. == "success" or . == "skipped" or . == "neutral")) then "success"
    else "unknown"
    end
  ')
  
  if [[ "$status" == "failure" ]] || [[ "$check_conclusion" == "failure" ]]; then
    echo "  ❌ CI failed for $version_name"
    all_passed=false
    failed_versions="${failed_versions}${version_name} "
  elif [[ "$check_conclusion" == "pending" ]] || ([[ "$status" == "pending" ]] && [[ "$status_count" -gt 0 ]]); then
    echo "  ⏳ CI still running for $version_name"
    all_passed=false
    failed_versions="${failed_versions}${version_name}(pending) "
  elif [[ "$status" == "unknown" ]] && [[ "$check_conclusion" == "unknown" ]]; then
    echo "  ⚠️ Could not verify CI status for $version_name (API error)"
    all_passed=false
    failed_versions="${failed_versions}${version_name}(unknown) "
  elif [[ "$status" == "success" ]] || [[ "$check_conclusion" == "success" ]]; then
    echo "  ✅ CI passed for $version_name"
  elif [[ "$status_count" -eq 0 ]] && [[ "$check_count" -eq 0 ]]; then
    echo "  ℹ️ No CI checks found for $version_name (assuming OK)"
  elif [[ "$status" == "pending" ]] && [[ "$status_count" -eq 0 ]] && [[ "$check_conclusion" == "no_checks" ]]; then
    echo "  ℹ️ No CI checks found for $version_name (assuming OK)"
  else
    echo "  ⚠️ Unexpected CI state for $version_name: status=$status, check_conclusion=$check_conclusion"
    all_passed=false
    failed_versions="${failed_versions}${version_name}(unexpected) "
  fi
done < <(echo "$versions_json" | jq -r '.[] | "\(.version)|\(.hash)|\(.version_name)"')

echo ""
[[ "$all_passed" == "true" ]] && echo "ci_passed=true" || echo "ci_passed=false"
