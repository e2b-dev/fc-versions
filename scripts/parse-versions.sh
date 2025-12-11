#!/bin/bash
# Parse versions from firecracker_versions.txt and output as JSON array

set -euo pipefail

VERSIONS_FILE="${1:-firecracker_versions.txt}"

if [[ ! -f "$VERSIONS_FILE" ]]; then
  echo "Error: $VERSIONS_FILE not found" >&2
  exit 1
fi

# Read versions, skip comments and empty lines, output as JSON array
grep -v '^ *#' "$VERSIONS_FILE" | grep -v '^$' | jq -R -s -c 'split("\n") | map(select(length > 0))'
