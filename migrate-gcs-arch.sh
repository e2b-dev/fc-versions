#!/bin/bash
# Copies flat-path firecracker binaries into amd64/ subdirectories in GCS.
#
# Before ARM64 support was added, builds were uploaded as:
#   firecrackers/{version_name}/firecracker
#
# The arch-aware layout expects:
#   firecrackers/{version_name}/amd64/firecracker
#
# This script finds flat-path binaries and copies them into the amd64/ subdir
# so the orchestrator's arch-based path resolution can find them.
#
# Usage:
#   ./migrate-gcs-arch.sh <bucket>                      # dry-run: show what would be copied
#   ./migrate-gcs-arch.sh <bucket> --apply               # copy flat -> amd64/
#   ./migrate-gcs-arch.sh <bucket> --delete-old          # dry-run: show what old flat files would be deleted
#   ./migrate-gcs-arch.sh <bucket> --delete-old --apply  # actually delete old flat files
#
# Recommended workflow:
#   1. ./migrate-gcs-arch.sh gs://my-bucket              # review what will be copied
#   2. ./migrate-gcs-arch.sh gs://my-bucket --apply       # copy to amd64/
#   3. ... verify everything works ...
#   4. ./migrate-gcs-arch.sh gs://my-bucket --delete-old  # review what will be deleted
#   5. ./migrate-gcs-arch.sh gs://my-bucket --delete-old --apply  # clean up old flat files

set -euo pipefail

BUCKET="${1:?Usage: $0 <bucket> [--apply] [--delete-old]}"
shift

APPLY=false
DELETE_OLD=false
for arg in "$@"; do
  case "$arg" in
    --apply)      APPLY=true ;;
    --delete-old) DELETE_OLD=true ;;
    *) echo "Unknown flag: $arg"; exit 1 ;;
  esac
done

# Strip gs:// prefix if provided, we add it back
BUCKET="${BUCKET#gs://}"

GCS_PREFIX="firecrackers"

echo "Scanning gs://${BUCKET}/${GCS_PREFIX} for flat-path firecracker binaries..."
echo ""

# Match only flat-path binaries: firecrackers/{version}/firecracker
# The single * does NOT match path separators, so this excludes
# firecrackers/{version}/{arch}/firecracker.
objects=$(gsutil ls "gs://${BUCKET}/${GCS_PREFIX}/*/firecracker" 2>/dev/null || true)

if [[ -z "$objects" ]]; then
  echo "No flat-path firecracker binaries found in gs://${BUCKET}/${GCS_PREFIX}"
  exit 0
fi

count=0
if [[ "$DELETE_OLD" == true ]]; then
  while IFS= read -r src; do
    [[ -z "$src" ]] && continue

    if [[ "$APPLY" == true ]]; then
      echo "  DELETE  $src"
      gsutil rm "$src"
    else
      echo "  [dry-run] would delete  $src"
    fi
    ((count++)) || true
  done <<< "$objects"

  echo ""
  echo "Total: $count objects"
  if [[ "$APPLY" != true ]]; then
    echo ""
    echo "This was a dry run. Add --apply to actually delete."
  fi
else
  while IFS= read -r src; do
    [[ -z "$src" ]] && continue

    # Insert /amd64 before the filename:
    #   .../firecrackers/v1.10.1/firecracker -> .../firecrackers/v1.10.1/amd64/firecracker
    dst="${src%/firecracker}/amd64/firecracker"

    if [[ "$APPLY" == true ]]; then
      echo "  COPY  $src"
      echo "    ->  $dst"
      gsutil cp "$src" "$dst"
    else
      echo "  [dry-run] $src"
      echo "         -> $dst"
    fi
    ((count++)) || true
  done <<< "$objects"

  echo ""
  echo "Total: $count objects"
  if [[ "$APPLY" != true ]]; then
    echo ""
    echo "This was a dry run. Add --apply to actually copy."
  fi
fi
