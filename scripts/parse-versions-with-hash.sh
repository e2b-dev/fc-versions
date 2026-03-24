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

versions=()

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "$line" ]] && continue

  # Split line into version spec and optional arch list
  version=$(echo "$line" | awk '{print $1}')
  arch_spec=$(echo "$line" | awk '{print $2}')

  # Arch column is required
  if [[ -z "$arch_spec" ]]; then
    echo "Error: missing architecture for version $version (e.g. 'v1.12.1 amd64,arm64')" >&2
    exit 1
  fi

  # Resolve version and hash
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

  # Emit one matrix entry per architecture
  IFS=',' read -ra archs <<< "$arch_spec"
  for arch in "${archs[@]}"; do
    versions+=("$(jq -n \
      --arg version "$version" \
      --arg hash "$fullhash" \
      --arg version_name "$version_name" \
      --arg arch "$arch" \
      '{version: $version, hash: $hash, version_name: $version_name, arch: $arch}')")
  done
done < "$OLDPWD/$VERSIONS_FILE"

printf '%s\n' "${versions[@]}" | jq -s -c '.'
