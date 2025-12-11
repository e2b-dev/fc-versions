#!/bin/bash

set -euo pipefail

VERSIONS_FILE="${1:-firecracker_versions.txt}"
FIRECRACKER_REPO_URL="${2:-https://github.com/e2b-dev/firecracker.git}"

if [[ ! -f "$VERSIONS_FILE" ]]; then
  echo "Error: $VERSIONS_FILE not found" >&2
  exit 1
fi

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

git clone --bare "$FIRECRACKER_REPO_URL" "$TEMP_DIR/fc-repo" 2>/dev/null
cd "$TEMP_DIR/fc-repo"

versions_json="["
first=true

while IFS= read -r version || [[ -n "$version" ]]; do
  [[ "$version" =~ ^[[:space:]]*# ]] && continue
  [[ -z "$version" ]] && continue
  
  if [[ "$version" =~ ^([^_]+)_([0-9a-fA-F]+)$ ]]; then
    tag="${BASH_REMATCH[1]}"
    shorthash="${BASH_REMATCH[2]}"
    fullhash=$(git rev-parse --verify "$shorthash^{commit}" 2>/dev/null || echo "")
    if [[ -z "$fullhash" ]]; then
      echo "Error: Could not resolve hash $shorthash for version $version" >&2
      exit 1
    fi
    version_name="${tag}_${shorthash}"
  else
    fullhash=$(git rev-parse --verify "${version}^{commit}" 2>/dev/null || echo "")
    if [[ -z "$fullhash" ]]; then
      echo "Error: Could not resolve commit for version $version" >&2
      exit 1
    fi
    if git rev-parse --verify "${version}^{tag}" >/dev/null 2>&1; then
      short_hash=$(git rev-parse --short "$fullhash")
      version_name="${version}_${short_hash}"
    else
      latest_tag=$(git describe --tags --abbrev=0 "$fullhash" 2>/dev/null || echo "")
      if [[ -n "$latest_tag" ]]; then
        short_hash=$(git rev-parse --short "$fullhash")
        version_name="${latest_tag}_${short_hash}"
      else
        version_name="$version"
      fi
    fi
  fi
  
  [[ "$first" == "true" ]] && first=false || versions_json+=","
  versions_json+=$(jq -n \
    --arg version "$version" \
    --arg hash "$fullhash" \
    --arg version_name "$version_name" \
    '{version: $version, hash: $hash, version_name: $version_name}')
done < "$OLDPWD/$VERSIONS_FILE"

echo "${versions_json}]"
