#!/bin/bash
# Copies flat-path firecracker binaries into amd64/ subdirectories in GCS.
#
# Before ARM64 support was added, builds were uploaded as:
#   {version_name}/firecracker
#
# The arch-aware layout expects:
#   {version_name}/amd64/firecracker
#
# This script finds flat-path binaries and copies them into the amd64/ subdir
# so the orchestrator's arch-based path resolution can find them.
#
# Usage:
#   ./scripts/migrate-gcs-arch.sh <bucket-or-path>          # dry-run: show what would be copied
#   ./scripts/migrate-gcs-arch.sh <bucket-or-path> --apply   # copy flat -> amd64/
#
# Examples:
#   ./scripts/migrate-gcs-arch.sh gs://e2b-staging-fc-versions
#   ./scripts/migrate-gcs-arch.sh gs://e2b-prod-public-builds/firecrackers --apply

set -euo pipefail

GCS_PATH="${1:?Usage: $0 <bucket-or-path> [--apply]}"
shift

APPLY=false
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=true ;;
    *) echo "Unknown flag: $arg"; exit 1 ;;
  esac
done

# Normalize: strip trailing slash
GCS_PATH="${GCS_PATH%/}"

echo "Scanning ${GCS_PATH} for flat-path firecracker binaries..."
echo ""

# Match only flat-path binaries: {version}/firecracker
# The single * does NOT match path separators, so this excludes
# {version}/{arch}/firecracker.
objects=$(gsutil ls "${GCS_PATH}/*/firecracker" 2>/dev/null || true)

if [[ -z "$objects" ]]; then
  echo "No flat-path firecracker binaries found in ${GCS_PATH}"
  exit 0
fi

copied=0
skipped=0
while IFS= read -r src; do
  [[ -z "$src" ]] && continue

  # Insert /amd64 before the filename:
  #   .../v1.10.1/firecracker -> .../v1.10.1/amd64/firecracker
  dst="${src%/firecracker}/amd64/firecracker"

  # Skip if destination already exists
  if gsutil -q stat "$dst" 2>/dev/null; then
    echo "  SKIP  $dst (already exists)"
    ((skipped++)) || true
    continue
  fi

  if [[ "$APPLY" == true ]]; then
    echo "  COPY  $src"
    echo "    ->  $dst"
    gsutil cp "$src" "$dst"
  else
    echo "  [dry-run] $src"
    echo "         -> $dst"
  fi
  ((copied++)) || true
done <<< "$objects"

echo ""
echo "Total: $copied to copy, $skipped skipped (already exist)"
if [[ "$APPLY" != true && "$copied" -gt 0 ]]; then
  echo ""
  echo "This was a dry run. Add --apply to actually copy."
fi
