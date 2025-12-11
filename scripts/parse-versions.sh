#!/bin/bash

set -euo pipefail

VERSIONS_FILE="${1:-firecracker_versions.txt}"

if [[ ! -f "$VERSIONS_FILE" ]]; then
  echo "Error: $VERSIONS_FILE not found" >&2
  exit 1
fi

grep -v '^ *#' "$VERSIONS_FILE" | grep -v '^$' | jq -R -s -c 'split("\n") | map(select(length > 0))'
